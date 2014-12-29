module Hasql.Postgres.Session.Transaction where

import Hasql.Postgres.Prelude
import qualified Database.PostgreSQL.LibPQ as PQ
import qualified Data.HashTable.IO as Hashtables
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy.Builder as BB
import qualified Data.ByteString.Lazy.Builder.ASCII as BB
import qualified Data.ByteString.Lazy as BL
import qualified Data.Vector as Vector
import qualified Hasql.Postgres.Session.Execution as Execution
import qualified Hasql.Postgres.Session.ResultProcessing as ResultProcessing
import qualified Hasql.Postgres.Statement as Statement


-- * Environment
-------------------------

data Env =
  Env {
    executionEnv :: Execution.Env,
    nameCounter :: IORef (Maybe Word16)
  }

newEnv :: Execution.Env -> IO Env
newEnv execution =
  Env <$> pure execution <*> newIORef Nothing


-- * Monad
-------------------------

newtype M r =
  M (ReaderT Env (EitherT Error IO) r)
  deriving (Functor, Applicative, Monad, MonadIO)

data Error =
  NotInTransaction |
  ResultProcessingError ResultProcessing.Error

run :: Env -> M r -> IO (Either Error r)
run e (M m) =
  runEitherT $ runReaderT m e

throwError :: Error -> M a
throwError e = M $ lift $ left $ e

liftExecution :: Execution.M a -> M a
liftExecution m =
  M $ ReaderT $ \e ->
    EitherT $ fmap (either (Left . ResultProcessingError) Right) $ 
    Execution.run (executionEnv e) m

-- |
-- Requires to be in transaction.
nextName :: M ByteString
nextName =
  do
    e <- M $ ask
    transactionState <- liftIO $ readIORef (nameCounter e)
    counter <- maybe (throwError NotInTransaction) return transactionState
    liftIO $ writeIORef (nameCounter e) (Just $ succ counter)
    return $ fromString $ 'x' : show counter

-- |
-- Returns a cursor identifier.
declareCursor :: Statement.Statement -> M Statement.Cursor
declareCursor s =
  do
    name <- nextName
    liftExecution $ 
      Execution.unitResult =<< 
      Execution.statement (Statement.declareCursor name s)
    return name

fetchFromCursor :: Int -> Statement.Cursor -> M (Vector (Vector (Maybe ByteString)))
fetchFromCursor amount cursor =
  liftExecution $
    Execution.vectorResult =<< 
    Execution.statement (Statement.fetchFromCursor amount cursor)

beginTransaction :: Statement.TransactionMode -> M ()
beginTransaction mode =
  do
    e <- M $ ask
    liftIO $ writeIORef (nameCounter e) (Just 0)
    liftExecution $ 
      Execution.unitResult =<< 
      Execution.statement (Statement.beginTransaction mode)

finishTransaction :: Bool -> M ()
finishTransaction commit =
  do
    liftExecution $ 
      Execution.unitResult =<< 
      Execution.statement (bool Statement.abortTransaction Statement.commitTransaction commit)
    e <- M $ ask
    liftIO $ writeIORef (nameCounter e) Nothing


-- * Stream
-------------------------

type Stream =
  ListT M (Vector (Maybe ByteString))

streamWithCursor :: Int -> Statement.Statement -> M Stream
streamWithCursor batching statement =
  do
    cursor <- declareCursor statement
    return $ 
      let loop = do
            chunk <- lift $ fetchFromCursor batching cursor
            guard $ not $ Vector.null chunk
            Vector.foldl step mempty chunk <> loop
          step z r = z <> pure r
          in loop


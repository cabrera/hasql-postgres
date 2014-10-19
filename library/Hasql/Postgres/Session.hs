module Hasql.Postgres.Session where

import Hasql.Postgres.Prelude hiding (Error)
import qualified Database.PostgreSQL.LibPQ as L
import qualified Hasql.Postgres.OID as OID
import qualified Hasql.Postgres.Renderer as Renderer
import qualified Hasql.Postgres.Statement as Statement
import qualified Hasql.Postgres.TemplateConverter as TemplateConverter
import qualified Hasql.Postgres.LibPQ.Result as Result
import qualified Hasql.Postgres.LibPQ.StatementPreparer as StatementPreparer


type Context =
  (L.Connection, StatementPreparer.StatementPreparer, IORef (Maybe Word))

newContext :: L.Connection -> IO Context
newContext c = 
  (,,) <$> pure c <*> StatementPreparer.new c <*> newIORef Nothing


-- * Errors
-------------------------

data Error =
  NotInTransaction |
  UnexpectedResult Text |
  ResultError Result.Error |
  UnparsableTemplate ByteString Text
  deriving (Show, Typeable)


-- * Session
-------------------------

type Session =
  ReaderT Context (ExceptT Error IO)

-- |
-- A width of a row and a stream of serialized values.
type Stream =
  (Int, ListT Session (Maybe ByteString))

-- |
-- Execute the session, throwing the exceptions.
run :: Context -> Session r -> IO (Either Error r)
run c s =
  runExceptT $ runReaderT s c

parseResult :: Maybe L.Result -> Session Result.Success
parseResult r =
  ReaderT $ \(c, _, _) -> lift (Result.parse c r) >>= either (throwError . ResultError) return

execute :: Statement.Statement -> Session Result.Success
execute s =
  parseResult =<< do
    (connection, preparer, _) <- ask
    let (template, params, preparable) = s
    convertedTemplate <-
      either (throwError . UnparsableTemplate template) return $ TemplateConverter.convert template
    case preparable of
      True -> do
        let (tl, vl) = unzip params
        key <- lift $ withExceptT ResultError $ StatementPreparer.prepare convertedTemplate tl preparer
        liftIO $ L.execPrepared connection key vl L.Text
      False -> do
        let params' = map (\(t, v) -> (\(vb, vf) -> (t, vb, vf)) <$> v) params
        liftIO $ L.execParams connection convertedTemplate params' L.Text

-- |
-- Requires to be in transaction.
nextName :: Session ByteString
nextName =
  do
    (_, _, transactionStateRef) <- ask
    transactionState <- liftIO $ readIORef transactionStateRef
    nameCounter <- maybe (throwError NotInTransaction) return transactionState
    liftIO $ writeIORef transactionStateRef (Just $ succ nameCounter)
    return $ Renderer.run nameCounter $ \n -> Renderer.char 'v' <> Renderer.word n

unitResult :: Result.Success -> Session ()
unitResult =
  \case
    Result.CommandOK _ -> return ()
    _ -> throwError $ UnexpectedResult "Not a unit"

streamResult :: Result.Success -> Session Stream
streamResult =
  \case
    Result.Stream (w, l) -> return (w, hoist liftIO l)
    _ -> throwError $ UnexpectedResult "Not a stream"

rowsAffectedResult :: Result.Success -> Session ByteString
rowsAffectedResult =
  \case
    Result.CommandOK (Just n) -> return n
    _ -> throwError $ UnexpectedResult "Not an affected rows number"

-- |
-- Returns the cursor identifier.
declareCursor :: Statement.Statement -> Session Statement.Cursor
declareCursor statement =
  do
    name <- nextName
    unitResult =<< execute (Statement.declareCursor name statement)
    return name

closeCursor :: Statement.Cursor -> Session ()
closeCursor cursor =
  unitResult =<< execute (Statement.closeCursor cursor)

fetchFromCursor :: Statement.Cursor -> Session Stream
fetchFromCursor cursor =
  streamResult =<< execute (Statement.fetchFromCursor cursor)

beginTransaction :: Statement.TransactionMode -> Session ()
beginTransaction mode =
  do
    (_, _, transactionStateRef) <- ask
    liftIO $ writeIORef transactionStateRef (Just 0)
    unitResult =<< execute (Statement.beginTransaction mode)

finishTransaction :: Bool -> Session ()
finishTransaction commit =
  do
    unitResult =<< execute (bool Statement.abortTransaction Statement.commitTransaction commit)
    (_, _, transactionStateRef) <- ask
    liftIO $ writeIORef transactionStateRef Nothing

inTransaction :: Statement.TransactionMode -> Session r -> Session r
inTransaction mode session =
  do
    beginTransaction mode
    r <- 
      catchError session $ 
        \case
          ResultError e@(Result.ResultError _ state _ _ _) -> do
            finishTransaction False
            -- inTransaction mode session
            $bug $ "Unimplemented error handling: " <> show e
          e -> do
            finishTransaction False
            throwError e
    finishTransaction True
    return r

streamWithCursor :: Statement.Statement -> Session Stream
streamWithCursor statement =
  do
    cursor <- declareCursor statement
    connection <- ask
    (w, l) <- fetchFromCursor cursor
    let remainder =
          forever $ join $ fmap snd $ lift $ fetchFromCursor cursor
    return (w, l <> remainder)


module Hasql.Postgres.TemplateConverter where

import Hasql.Postgres.Prelude
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Builder as BB
import qualified Data.ByteString.Lazy.Builder.ASCII as BB
import qualified Hasql.Postgres.TemplateConverter.Parser as Parser


-- |
-- 
-- >>> convert "asdf ? \"'\\\"?'\" d 2??"
-- Right "asdf $1 \"'\\\"?'\" d 2$2$3"
convert :: ByteString -> Either Text ByteString
convert t =
  do
    parts <- Parser.run t Parser.parts
    return $
      BL.toStrict $ BB.toLazyByteString $ mconcat $ ($ 1) $ evalState $ do
        forM parts $ \case
          Parser.Chunk c -> do
            return c
          Parser.Placeholder -> do
            i <- get
            put $ succ i
            return $ BB.char8 '$' <> BB.wordDec i


-- |
-- Mid-level abstractions over gritty details of \"lib-pq\".
module HighSQLPostgres.LibPQ.Connector where

import HighSQLPostgres.Prelude hiding (Error)
import qualified Database.PostgreSQL.LibPQ as L
import qualified HighSQLPostgres.Renderer as Renderer


data Settings =
  Settings {
    host :: ByteString,
    port :: Word16,
    user :: Text,
    password :: Text,
    database :: Text
  }


-- |
-- Default settings.
settings :: Settings
settings =
  Settings "127.0.0.1" 5432 "postgres" "" ""


data Error =
  BadStatus (Maybe ByteString) |
  UnsupportedVersion Int
  deriving (Show, Typeable)


-- |
-- Establish and initialize a connection.
open :: Settings -> ExceptT Error IO L.Connection
open s =
  do
    c <- lift $ L.connectdb (Renderer.run s settingsRenderer)
    do
      s <- lift $ L.status c
      when (s /= L.ConnectionOk) $ 
        do
          m <- lift $ L.errorMessage c
          throwError $ BadStatus m
    do
      v <- lift $ L.serverVersion c
      when (v < 80200) $ throwError $ UnsupportedVersion v
    lift $ L.exec c "SET standard_conforming_strings TO on;SET datestyle TO ISO"
    return c


settingsRenderer :: Renderer.R Settings
settingsRenderer s =
  mconcat $ intersperse " " args
  where
    args =
      [
        "host="     <> Renderer.byteString (host s),
        "port="     <> Renderer.word16 (port s),
        "user="     <> Renderer.text (user s),
        "password=" <> Renderer.text (password s),
        "dbname="   <> Renderer.text (database s)
      ]
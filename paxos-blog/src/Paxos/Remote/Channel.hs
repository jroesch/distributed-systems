{-# LANGUAGE DeriveGeneric, DefaultSignatures, BangPatterns #-}
module Paxos.Remote.Channel where

import Control.Concurrent (forkIO)
import qualified Control.Concurrent.Chan as C
import Control.Monad
import Control.Monad.Trans (lift)
import Control.Monad.Trans.Either
import qualified Data.ByteString as B
import Data.IORef
import Data.Serialize
import Data.Serialize.Get
import Data.Word
import GHC.IO.Handle
import GHC.Generics
import Network

{- data Chan a = LocalChan (C.Chan a)
            | RemoteChan Connection


data ChanMessage a = Write a
                   | Read
                   deriving (Show, Eq)

data Connection = Connection ConnectionInfo Handle deriving (Eq, Show)
data ConnectionInfo = ConnectionInfo deriving (Show, Eq, Generic)

instance Serialize ConnectionInfo

instance Serialize PortID where
  get = do
    word <- getWord32be
    return $ PortNumber $ fromIntegral word

  put (PortNumber p) = do
    putWord32be $ fromIntegral p

newChan :: (Serialize a) => IO (Chan a)
newChan = newChan >>= (return . LocalChan)

writeChan :: (Serialize a) => Chan a -> a -> IO ()
writeChan (LocalChan messages) val = 
  C.writeChan messages val
writeChan (RemoteChan conn) val =
  writeA conn (Write val)

readChan :: (Serialize a) => Chan a -> IO a
readChan (LocalChan messages) = C.readChan messages 
readChan (RemoteChan conn res) = do
  writeA conn Read
  readA conn

openChan :: String -> PortID -> IO (Chan a)
openChan s p = do
  conn <- openConnection s p
  return $ RemoteChan conn

openConnection :: String -> PortID -> IO Connection
openConnection host port = execE $ do 
    handle <- lift $ connectTo host port
    size <- lift $ B.hGet handle 4
    s' <- hoistEither $ decode size     
    connectData <- lift $ B.hGet handle $ s'
    info <- hoistEither $ decode connectData
    return $ Connection info handle

channelSocket :: IO Socket
channelSocket = listenOn (PortID $ fromIntegral 9000)

receiveConnections :: (Serialize a) => Socket -> (ChanMessage a -> IO ()) -> IO ()
receiveConnections socket = forever $ do
  (handle, hname, port) <- accept socket
  let conn = Connection ConnectionInfo handle
  forkIO $ forever $ do
    writeA conn ConnectionInfo
    r <- readA conn
    handler r
    return ()
        
readA :: (Serialize a) => Connection -> IO a
readA (Connection _ handle) = execE $ do
  size <- lift $ B.hGet handle 2
  s' <- hoistEither $ decode size
  bytes <- lift $ B.hGet handle s'
  hoistEither $ decode bytes
  
writeA :: (Serialize a) => Connection -> a -> IO ()
writeA (Connection _ handle) val = do
    let bytes = encode val
        len = (fromIntegral $ B.length bytes) :: Word32
    B.hPut handle $ B.concat [encode len, bytes]

-- Helper Functions
execE :: (Show e, Functor m) => EitherT e m a -> m a
execE e = let me = runEitherT e
              in fmap forceErr me

forceErr :: (Show e) => Either e a -> a
forceErr r = case r of
  Left e   -> error $ show e
  Right r' -> r' -}

data Chan a = LocalChan (C.Chan a)
            | RemoteChan Connection

data Connection = Connection ConnectionInfo Handle deriving (Eq, Show)
data ConnectionInfo = ConnectionInfo !String !PortID !Int deriving (Show, Eq, Generic)

instance Serialize ConnectionInfo

instance Serialize PortID where
  get = do
    word <- getWord32be
    return $ PortNumber $ fromIntegral word

  put (PortNumber p) = do
    putWord32be $ fromIntegral p


sysInitialized :: IO (IORef Bool)
sysInitialized = newIORef False 

startChannelService :: String -> PortID -> IO Connection
startChannelService host port = execE $ do 
    handle <- lift $ connectTo host port -- open
    size <- lift $ B.hGet handle 4
    s' <- hoistEither $ decode size     
    connectData <- lift $ B.hGet handle $ s'
    info <- hoistEither $ decode connectData
    return $ Connection info handle
  

startChannelService = forever $ do
  (handle, hname, port) <- accept socket
  let conn = Connection ConnectionInfo handle
  forkIO $ forever $ do
    writeA conn ConnectionInfo
    r <- readA conn
    handler r
    return ()

-- Helper Functions
execE :: (Show e, Functor m) => EitherT e m a -> m a
execE e = let me = runEitherT e
              in fmap forceErr me

forceErr :: (Show e) => Either e a -> a
forceErr r = case r of
  Left e   -> error $ show e
  Right r' -> r'



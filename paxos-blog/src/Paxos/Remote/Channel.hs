{-# LANGUAGE DeriveGeneric, DefaultSignatures, BangPatterns, GADTs, EmptyDataDecls, OverloadedStrings #-}
module Paxos.Remote.Channel (
   Chan,
   newChan,
   writeChan,
   readChan,
   openReadChan,
   openWriteChan,
   channelRegistry,
   startChannelService
  ) where

import Control.Concurrent (forkIO)
import qualified Control.Concurrent.Chan as C
import Control.Concurrent.MVar
import Control.Monad
import Control.Monad.Trans (lift)
import Control.Monad.Trans.Either
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import Data.Functor ((<$>))
import Data.IORef
import Data.Serialize
import Data.Serialize.Get
import Data.Word
import qualified Data.Array as A
import Data.Array ((!))
import GHC.IO.Handle
import GHC.Generics
import Network
import System.Log.Logger
import Debug.Trace

type Message = String

-- | Channel type with two GADT constructors representing locality of
-- channels.
data Chan a t where
    WriteChan :: Connection -> Chan a WriteMode
    ReadChan  :: (C.Chan a) -> Chan a ReadMode

-- | Phantom type for Chan
data ReadMode

-- | Phatom type for Chan
data WriteMode

-- | Message type for opening a channel.
data ChannelMode = NewChan
                 | OpenChan !Int
                 deriving (Show, Eq, Generic)

instance Serialize ChannelMode

-- | Represents a connection to a remote channel.
data Connection = Connection !ConnectionInfo !Handle deriving (Eq, Show)

-- | Contains the connection info and channel slot.
data ConnectionInfo = ConnectionInfo !String !PortNumber !Int deriving (Show, Eq, Generic)

instance Serialize ConnectionInfo

instance Serialize PortNumber where
  get = do
    word <- getWord32be
    return $ fromIntegral word

  put p = do
    putWord32be $ fromIntegral p

-- | A global registry for open channels.
type ChannelRegistry a = (MVar (ChannelData a))

-- | Channel data that keeps track of free slots, and an array of channels.
data ChannelData a = ChannelData ![Int] (A.Array Int (MVar (C.Chan a)))

newChan :: (Serialize a) => String -> Int -> IO (Chan a WriteMode)
newChan h p = WriteChan <$> connectToProcess h p NewChan

writeChan :: (Serialize a) => Chan a WriteMode -> a -> IO ()
writeChan (WriteChan (Connection _ handle)) v = hWrite handle v

readChan :: (Serialize a) => Chan a ReadMode -> IO a
readChan (ReadChan c) = C.readChan c

openReadChan :: (Serialize a) => (MVar (ChannelData a)) -> Int -> IO (Chan a ReadMode)
openReadChan ref slot = ReadChan <$> lookupChannel ref slot

openWriteChan :: (Serialize a) => String -> Int -> Int -> IO (Chan a WriteMode)
openWriteChan h p slot = WriteChan <$> connectToProcess h p (OpenChan slot)

-- | Start the channel service which allows remote processes to open
-- a channel.
startChannelService :: (Serialize a) => ChannelRegistry a -> IO ()
startChannelService reg = do
  socket <- trace "listening" $ listenOn $ PortNumber 9000
  forever $ do
    (handle, hname, port) <- trace "accepting on socket" $ accept socket
    forkIO $ execE $ do
      msg <- trace "reading data" $ lift $ hRead handle
      chan <- lift $ case msg of
        OpenChan slot -> lookupChannel reg slot
        NewChan -> do
          putStrLn "Here Dog"
          (slot, chan) <- allocateChannel reg
          hWrite handle slot
          return chan
      lift $ forever $ do
        msg <- hRead handle
        C.writeChan chan msg

-- | Connect to remote process given hostname and port number and channel
-- mode.
connectToProcess :: String -> Int -> ChannelMode -> IO Connection -- fix portnumber buissness
connectToProcess host port mode = do 
  handle <- trace "connecting to Process" $ connectTo host (PortNumber $ fromIntegral port) -- open
  hWrite handle mode
  slot <- hRead handle
  return $ Connection (ConnectionInfo host (fromIntegral port) slot) handle -- hardcoded slot number

-- | A registry for open channels.
channelRegistry :: IO (ChannelRegistry a)
channelRegistry = do
  mvars <- mapM (\_ -> newEmptyMVar) [0..99]
  let chanArray = A.listArray (0, 99) mvars 
  newMVar (ChannelData [0..99] chanArray)

-- | Allocate a channel in the channel registry, the return is a pair of 
-- the channel descriptor and the channel itself.
allocateChannel :: ChannelRegistry a -> IO (Int, (C.Chan a))
allocateChannel mvar = do
  registry <- takeMVar mvar
  case registry of
    (ChannelData [] array) ->
      error "No more avalible channels"
    (ChannelData (e:es) array) -> do
      let cvar = array ! e
      chan <- C.newChan
      putStrLn "putting Var"
      putMVar cvar chan
      putStrLn "Unputting Var"
      putMVar mvar (ChannelData es array)
      return (e, chan)

-- | Lookup a channel based on its channel descriptor.
lookupChannel :: ChannelRegistry a -> Int -> IO (C.Chan a)
lookupChannel mvar e = do
  (ChannelData _ array) <- takeMVar mvar
  let cvar = array ! e
  readMVar cvar

-- | Free a channel from the channel registry.
freeChannel :: ChannelRegistry a -> Int -> IO ()
freeChannel mvar e = do
  registry <- takeMVar mvar
  case registry of
    (ChannelData es array) -> do
      let cvar = array ! e
      _ <- takeMVar cvar
      putMVar mvar (ChannelData (e:es) array)

-- | Reads a value from a Handle in the form of a strict ByteString.
hRead :: (Serialize a) => Handle -> IO a
hRead h = execE $ do
  sizeBytes <- lift $ B.hGet h 8
  size <- hoistEither $ (decode sizeBytes :: Either String Int)
  dat <- lift $ B.hGet h size
  (hoistEither $ decode dat)

-- | Writes a value's length, followed by the value itself to a Handle.
hWrite :: (Serialize a) => Handle -> a -> IO ()
hWrite h val = 
  let msg = encode val
      len = encode $ (B.length msg)
  in B.hPut h $ B.append len msg

-- | Runs an EitherT to completion or forces an exception.
execE :: (Functor m) => EitherT String m a -> m a
execE e = let me = runEitherT e
              in fmap forceErr me
  where forceErr r = case r of
          Left e   -> error $ show e
          Right r' -> r'


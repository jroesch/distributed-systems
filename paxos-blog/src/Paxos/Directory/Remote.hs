{-# LANGUAGE DeriveGeneric, TupleSections #-}
module Paxos.Directory.Remote 
  ( Directory,
    Process,
    Pid,
    mkDirectory,
    plookup,
    send,
    receive,
    broadcast
  ) where

import Control.Concurrent.MVar
import Control.Monad
import Data.Functor ((<$>))
import qualified Data.Map as M
import Data.Serialize
import GHC.Generics
import qualified Paxos.Remote.Channel as R
import Paxos.Message (Message)

type Pid = Int

data Process = Process Pid (R.Chan RemoteMessage)

data RemoteMessage = APid Pid 
                   | AMessage Message 
                   deriving (Show, Generic)

instance Serialize RemoteMessage
  
instance Show Process where
  show (Process pid _) = "Process " ++ show pid

type Config = [(Pid, String, Int)]
type Directory = MVar (M.Map Pid (MVar Process))

-- need help here
mkDirectory :: Pid -> Config -> IO Directory
mkDirectory this config = do
    reg <- R.channelRegistry
    dir <- newMVar M.empty
    R.startChannelService reg (handler dir) -- other processes will start to fill my slots
    let connectList = filter ((> this) . third) config
    forM_ connectList $ \(pid, h, p) -> do
      rawChan <- R.newChan h p
      R.writeChan rawChan (APid pid)
      process <- newMVar $ (Process pid rawChan) 
      modifyMVar_ dir $ \x -> return $ M.insert pid process x
      return ()
    return dir
  where handler dir chan = modifyMVar_ dir $ \d -> do
          APid pid <- R.readChan chan
          if pid > this
            then error "Something is going wrong."
            else do 
              p <- newMVar (Process pid chan)
              return $ M.insert pid p d
        third (_, _, z) = z

plookup :: Directory -> Pid -> IO Process
plookup mdir pid = do
    dir <- readMVar mdir
    case pid `M.lookup` dir of
      Nothing -> error "NO PID #YOLO"
      Just v  -> readMVar v

send :: Directory -> Pid -> Message -> IO ()
send dir pid msg = do
    (Process _ chan) <- plookup dir pid
    R.writeChan chan (AMessage msg)

receive :: Process -> IO Message
receive (Process _ chan) = do
    c <- R.readChan chan 
    case c of
      AMessage m -> return m
      APid _     -> error "fucking pid"

broadcast :: Directory -> Message -> IO ()
broadcast d m = mapM_ writeMessage processes 
  where processes = undefined -- map snd $ M.toList d what to do here?
        writeMessage (Process _ chan) = R.writeChan chan $ AMessage m

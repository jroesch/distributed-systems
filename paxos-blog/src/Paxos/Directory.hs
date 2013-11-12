{-# LANGUAGE TupleSections #-}
module Paxos.Directory 
  ( Directory,
    Process,
    Pid,
    mkDirectory,
    plookup,
    send,
    receive,
    broadcast
  ) where

import qualified Control.Concurrent.Chan as C
import Data.Functor ((<$>))
import qualified Data.Map as M
import Paxos.Message (Message)

type Pid = Int

data Process = Process Pid (C.Chan Message) deriving (Eq)

instance Show Process where
  show (Process pid _) = "Process " ++ show pid

type Directory = M.Map Pid Process

mkDirectory :: [Pid] -> IO Directory
mkDirectory ps = do
    pairs <- sequence $ zipWith (\p -> fmap (p,)) ps $ map mkProcess ps
    return $ M.fromList pairs
  where mkProcess pid = (Process pid) <$> C.newChan
        
plookup :: Directory -> Pid -> Process
plookup dir pid = case pid `M.lookup` dir of
  Nothing -> error "NO PID #YOLO"
  Just v  -> v

send :: Directory -> Pid -> Message -> IO ()
send dir pid msg = 
  let (Process _ chan) = plookup dir pid in
    C.writeChan chan msg

receive :: Process -> IO Message
receive (Process _ chan) = C.readChan chan

broadcast :: Directory -> Message -> IO ()
broadcast d m = mapM_ writeMessage processes 
  where processes = map snd $ M.toList d
        writeMessage (Process _ chan) = C.writeChan chan m

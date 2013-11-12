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

import Paxos.Directory.Local

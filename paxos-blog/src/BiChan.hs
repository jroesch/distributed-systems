module Paxos.BiChan where

import Control.Monad
import Control.Concurrent.Chan

data BiChan a = BiChan (Chan a) (Chan a)

send :: BiChan a -> a -> IO ()
send (BiChan s _) v = writeChan s v

receive :: BiChan a -> IO a
receive (BiChan _ r) v = readChan r v

duplicate :: BiChan a -> BiChan a
duplicate (BiChan s r) = BiChan (dupChan s) (dupChan r)


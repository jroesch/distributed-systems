module Paxos.BiChan
  ( newBiChan,
    send,
    receive,
    duplicate
  ) where 
    
import Control.Monad
import Control.Concurrent.Chan

data BiChan a = BiChan (Chan a) (Chan a)

newBiChan :: IO (BiChan a)
newBiChan = do
  s <- newChan
  r <- newChan
  return $ BiChan s r

send :: BiChan a -> a -> IO ()
send (BiChan s _) v = writeChan s v

receive :: BiChan a -> IO a
receive (BiChan _ r) = readChan r

duplicate :: BiChan a -> IO (BiChan a)
duplicate (BiChan s r) = do
  s' <- dupChan s
  r' <- dupChan r
  return $ BiChan s' r'


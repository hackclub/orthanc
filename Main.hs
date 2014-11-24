{-# LANGUAGE TemplateHaskell, UnicodeSyntax #-}

import System.Environment (getArgs)
import Control.Monad (forever, forM_, sequence)
import Control.Distributed.Process
import Control.Distributed.Process.Backend.SimpleLocalnet
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node

replyBack :: (ProcessId, String) -> Process ()
replyBack (sender, msg) = send sender msg

logMessage :: String -> Process ()
logMessage msg = say $ "handling " ++ msg

githubName :: String -> String
githubName username =
	"Zach Latta"

slave :: (ProcessId, ProcessId) -> Process ()
slave (master, workQueue) = do
		us <- getSelfPid
		go us
	where
		go us = do
			send workQueue us

			receiveWait
				[ match $ \username  -> send master (githubName username) >> go us
				, match $ \() -> return ()
				]

remotable ['slave]

accStrings = go []
	where
		go :: [String] -> Int -> Process [String]
		go acc 0 = return $ reverse acc
		go acc n = do
			m <- expect
			go (m : acc) (n - 1)

master :: [String] -> [NodeId] -> Process [String]
master usernames slaves = do
	us <- getSelfPid

	workQueue <- spawnLocal $ do
		-- Reply with the next bit of work to be done
		sequence $ f usernames
			where f u = do
				them <- expect
				send them u
		--  Once all the work is done, tell the slaves to terminate
		forever $ do
			pid <- expect
			send pid ()

	-- Start slave processes
	forM_ slaves $ \nid -> spawn nid ($(mkClosure 'slave) (us, workQueue))

	-- Wait for the result
	accStrings (fromIntegral n)

rtable :: RemoteTable
rtable = __remoteTable initRemoteTable

main :: IO ()
main = do
	args <- getArgs

	case args of
		["master", host, port, n] -> do
			backend <- initializeBackend host port rtable
			startMaster backend $ \slaves -> do
				result <- master (read n) slaves
				liftIO $ print result
		["slave", host, port] -> do
			backend <- initializeBackend host port rtable
			startSlave backend

{-# LANGUAGE TemplateHaskell, UnicodeSyntax #-}

import Control.Distributed.Process
import Control.Distributed.Process.Backend.SimpleLocalnet
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node
import Control.Monad (forever, forM_, sequence)
import Data.Maybe
import qualified Github.Users as Github
import qualified Github.Data.Definitions as Github
import System.Environment (getArgs)

replyBack :: (ProcessId, String) -> Process ()
replyBack (sender, msg) = send sender msg

logMessage :: String -> Process ()
logMessage msg = say $ "handling " ++ msg

githubName :: String -> IO String
githubName username = do
	r ← Github.userInfoFor username
	return $ case r of
		Left e → "Error: " ++ show e
		Right uinfo → clean $ Github.detailedOwnerName uinfo
			where
				clean Nothing = username
				clean (Just "") = username
				clean (Just realName) = realName

slave :: (ProcessId, ProcessId) -> Process ()
slave (master, workQueue) = do
		us <- getSelfPid
		go us
	where
		go us = do
			send workQueue us
			receiveWait
				[ match $ \nm -> liftIO(githubName nm) >>= send master >> go us
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
		sequence $ map (\u → expect >>= \them→send them u) usernames
		forever $ expect >>= \pid → send pid ()

	forM_ slaves $ \nid -> spawn nid ($(mkClosure 'slave) (us, workQueue))
	accStrings $ length usernames

rtable :: RemoteTable
rtable = __remoteTable initRemoteTable

main :: IO ()
main = do
	args <- getArgs

	case args of
		("master" : host : port : usernames) -> do
			backend <- initializeBackend host port rtable
			startMaster backend $ \slaves -> do
				result <- master usernames slaves
				liftIO $ print result

		["slave", host, port] -> do
			backend <- initializeBackend host port rtable
			startSlave backend

		_ -> putStrLn "Get your shit together"

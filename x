-- Step 1: Identify IsClinicClient
WITH IsClinicClients AS (
    SELECT CLIENTID, 1 AS IsClinicClient
    FROM dbo.CLIENTACCOUNTS
    WHERE CLIENTACCOUNT < 100000
),

-- Step 2: Determine client matches by branching only into the appropriate logic
BranchResults AS (
    -- Sub-client or Clinic
    SELECT 
        s.myScreenuserID,
        s.ClientTypeID,
        s.ClientID AS SubscriberClientID,
        s.DynamicClientID AS SubscriberDynamicClientID,
        ca.ClientID
    FROM #subscribers s
    LEFT JOIN IsClinicClients ic ON ic.CLIENTID = s.ClientID
    JOIN dbo.CLIENTACCOUNTS ca WITH (NOLOCK)
        ON ca.CLIENTID = s.ClientID AND ca.ACTIVE = 1
    WHERE s.ClientTypeID = 0 OR ic.IsClinicClient = 1

    UNION ALL

    -- Master
    SELECT 
        s.myScreenuserID,
        s.ClientTypeID,
        s.ClientID AS SubscriberClientID,
        s.DynamicClientID AS SubscriberDynamicClientID,
        ca.ClientID
    FROM #subscribers s
    LEFT JOIN IsClinicClients ic ON ic.CLIENTID = s.ClientID
    JOIN dbo.CLIENTACCOUNTS master WITH (NOLOCK)
        ON master.CLIENTID = s.ClientID AND master.ACTIVE = 1
    JOIN dbo.CLIENTACCOUNTS ca WITH (NOLOCK)
        ON ca.CLIENTACCOUNT = master.CLIENTACCOUNT AND ca.ACTIVE = 1
    WHERE s.ClientTypeID = 1 AND ic.IsClinicClient IS NULL

    UNION ALL

    -- Dynamic
    SELECT 
        s.myScreenuserID,
        s.ClientTypeID,
        s.ClientID AS SubscriberClientID,
        s.DynamicClientID AS SubscriberDynamicClientID,
        ca.ClientID
    FROM #subscribers s
    LEFT JOIN IsClinicClients ic ON ic.CLIENTID = s.ClientID
    CROSS APPLY dbo.fn_DCG_GetClientIDsForDynamicClientID(s.DynamicClientID) ca
    WHERE s.ClientTypeID = 3 AND ic.IsClinicClient IS NULL
),

-- Step 3: Only keep rows where ClientID matches original subscriber’s ClientID
MatchingClients AS (
    SELECT *
    FROM BranchResults
    WHERE ClientID = SubscriberClientID
),

-- Step 4: Join with notification subscriptions for insert
FinalData AS (
    SELECT 
        mc.myScreenuserID,
        ns.myScreenUserNotificationTypeID,
        mc.ClientID,
        mc.SubscriberDynamicClientID
    FROM MatchingClients mc
    JOIN dbo.myScreenLogon mel ON mel.UserID = mc.myScreenuserID
    JOIN dbo.myScreenUserNotificationSubscriptions ns ON ns.myScreenUserID = mel.UserID
    WHERE ns.myScreenUserNotificationTypeID IN (1, 4)
      AND (ns.EmailAddressVerified = 1 OR ns.TextNumberVerified = 1)
)

-- Final insert
INSERT INTO #subscriberstonotify (myScreenuserID, myScreenUserNotificationTypeID, ClientID, DynamicClientID)
SELECT myScreenuserID, myScreenUserNotificationTypeID, ClientID, SubscriberDynamicClientID
FROM FinalData;

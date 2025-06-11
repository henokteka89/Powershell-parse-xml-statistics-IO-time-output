-- Assuming #subscribers is already populated

-- Step 1: Identify IsClinicClient
WITH IsClinicClients AS (
    SELECT CLIENTID, 1 AS IsClinicClient
    FROM dbo.CLIENTACCOUNTS
    WHERE CLIENTACCOUNT < 100000
),

-- Step 2: Expand subscribers with client classification and join with appropriate CLIENT IDs
EligibleClients AS (
    SELECT 
        s.myScreenuserID,
        s.ClientID AS SubscriberClientID,
        s.ClientTypeID AS SubscriberClientType,
        s.DynamicClientID AS SubscriberDynamicClientID,
        ca.ClientID AS ClientID
    FROM #subscribers s
    LEFT JOIN IsClinicClients ic ON s.ClientID = ic.CLIENTID
    OUTER APPLY (
        -- Sub-client or clinic logic
        SELECT ca.ClientID
        FROM dbo.CLIENTACCOUNTS ca WITH (NOLOCK)
        WHERE 
            (s.ClientTypeID = 0 OR ic.IsClinicClient = 1)
            AND ca.CLIENTID = s.ClientID
            AND ca.ACTIVE = 1

        UNION ALL

        -- Master client logic
        SELECT ca.ClientID
        FROM dbo.CLIENTACCOUNTS ca WITH (NOLOCK)
        JOIN dbo.CLIENTACCOUNTS master ON master.CLIENTID = s.ClientID AND master.ACTIVE = 1
        WHERE 
            s.ClientTypeID = 1 AND ic.IsClinicClient IS NULL
            AND ca.CLIENTACCOUNT = master.CLIENTACCOUNT
            AND ca.ACTIVE = 1

        UNION ALL

        -- Dynamic client logic
        SELECT ca.ClientID
        FROM dbo.fn_DCG_GetClientIDsForDynamicClientID(s.DynamicClientID) ca
        WHERE s.ClientTypeID = 3 AND ic.IsClinicClient IS NULL
    ) ca
),

-- Step 3: Filter for users with verified email/text and eligible notification types
FinalData AS (
    SELECT 
        e.myScreenuserID,
        ns.myScreenUserNotificationTypeID,
        e.ClientID,
        e.SubscriberDynamicClientID
    FROM EligibleClients e
    JOIN dbo.myScreenLogon mel ON mel.UserID = e.myScreenuserID
    JOIN dbo.myScreenUserNotificationSubscriptions ns ON ns.myScreenUserID = mel.UserID
    WHERE ns.myScreenUserNotificationTypeID IN (1, 4)
      AND (ns.EmailAddressVerified = 1 OR ns.TextNumberVerified = 1)
)

-- Step 4: Insert final results into #subscriberstonotify
INSERT INTO #subscriberstonotify (myScreenuserID, myScreenUserNotificationTypeID, ClientID, DynamicClientID)
SELECT myScreenuserID, myScreenUserNotificationTypeID, ClientID, SubscriberDynamicClientID
FROM FinalData;

-- Optionally: Return results
SELECT * FROM #subscriberstonotify;

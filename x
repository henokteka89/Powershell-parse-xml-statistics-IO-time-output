-- 1. Prep IsClinic info
WITH IsClinic AS (
    SELECT CLIENTID
    FROM dbo.CLIENTACCOUNTS
    WHERE CLIENTACCOUNT < 100000
),

-- 2. Get per-subscriber logic path + matching clients
SubscriberClients AS (
    SELECT
        s.myScreenuserID,
        s.ClientTypeID,
        s.ClientID AS SubscriberClientID,
        s.DynamicClientID AS SubscriberDynamicClientID,
        ca.ClientID
    FROM #subscribers s
    LEFT JOIN IsClinic ic ON s.ClientID = ic.CLIENTID

    -- SUB-CLIENT / CLINIC LOGIC
    LEFT JOIN dbo.CLIENTACCOUNTS ca WITH (NOLOCK)
        ON (s.ClientTypeID = 0 OR ic.CLIENTID IS NOT NULL)
        AND ca.CLIENTID = s.ClientID
        AND ca.ACTIVE = 1

    -- MASTER CLIENT LOGIC
    LEFT JOIN dbo.CLIENTACCOUNTS master WITH (NOLOCK)
        ON s.ClientTypeID = 1 AND ic.CLIENTID IS NULL AND master.CLIENTID = s.ClientID AND master.ACTIVE = 1
    LEFT JOIN dbo.CLIENTACCOUNTS ca2 WITH (NOLOCK)
        ON s.ClientTypeID = 1 AND ic.CLIENTID IS NULL
        AND ca2.CLIENTACCOUNT = master.CLIENTACCOUNT
        AND ca2.ACTIVE = 1

    -- DYNAMIC LOGIC
    OUTER APPLY (
        SELECT ClientID
        FROM dbo.fn_DCG_GetClientIDsForDynamicClientID(s.DynamicClientID)
    ) ca3
    WHERE
        (
            -- Apply matching only to the correct type
            (s.ClientTypeID = 0 OR ic.CLIENTID IS NOT NULL AND ca.ClientID IS NOT NULL AND ca.ClientID = s.ClientID)
            OR
            (s.ClientTypeID = 1 AND ic.CLIENTID IS NULL AND ca2.ClientID IS NOT NULL AND ca2.ClientID = s.ClientID)
            OR
            (s.ClientTypeID = 3 AND ic.CLIENTID IS NULL AND ca3.ClientID = s.ClientID)
        )
),

-- 3. Join with myScreen data
Final AS (
    SELECT
        sc.myScreenuserID,
        ns.myScreenUserNotificationTypeID,
        sc.SubscriberClientID,
        sc.SubscriberDynamicClientID
    FROM SubscriberClients sc
    JOIN dbo.myScreenLogon mel ON mel.UserID = sc.myScreenuserID
    JOIN dbo.myScreenUserNotificationSubscriptions ns ON ns.myScreenUserID = mel.UserID
    WHERE ns.myScreenUserNotificationTypeID IN (1, 4)
      AND (ns.EmailAddressVerified = 1 OR ns.TextNumberVerified = 1)
)

-- 4. Final insert
INSERT INTO #subscriberstonotify (myScreenuserID, myScreenUserNotificationTypeID, ClientID, DynamicClientID)
SELECT
    myScreenuserID,
    myScreenUserNotificationTypeID,
    SubscriberClientID,
    SubscriberDynamicClientID
FROM Final;

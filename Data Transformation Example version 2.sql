USE KYeCourts;

-- ======================================================
-- Drop existing tables if they exist
-- ======================================================
DROP TABLE IF EXISTS #TempPersonNumbers;
DROP TABLE IF EXISTS #TempP2itoAddressIds;

-- ======================================================
-- ======================================================
SELECT pdata.PtyPerNumberOld
INTO #TempPersonNumbers
FROM
(
    SELECT i.fkxSiteId,
           pta.PtyPerNumberOld
    FROM CoreParty.P2iToAddress AS pta
        INNER JOIN CoreParty.PartyToInitiator AS pti
            ON pti.PartyToInitiatorId = pta.fkPartyToInitiatorId
        INNER JOIN CoreInitiator.Initiator AS i
            ON i.InitiatorId = pti.fkInitiatorId
    WHERE pta.PtyPerNumberOld LIKE '@%'
    GROUP BY i.fkxSiteId,
             pta.PtyPerNumberOld
    HAVING COUNT(1) > 1
) AS pdata;


-- ======================================================
-- ======================================================
DECLARE @P2itoAddressId INT,
        @MaxPtyPerNumberOld BIGINT,
        @PerNumber VARCHAR(16);


-- ======================================================
-- show current max pty per num old value
-- ======================================================
--SELECT @MaxPtyPerNumberOld;

-- ======================================================
-- ======================================================
CREATE TABLE #TempP2itoAddressIds
(
    P2itoAddressId INT,
    PerNumber VARCHAR(16)
);


-- ======================================================
-- build our temp p2itoaddressid table
-- ======================================================
WHILE EXISTS (SELECT TOP 1 * FROM #TempPersonNumbers)
BEGIN
    -- get the next PerNumber from the temp table
    SET @PerNumber =
    (
        SELECT TOP (1) tpn.PtyPerNumberOld FROM #TempPersonNumbers AS tpn
    );

    -- get the p2itoaddressid for this @PerNumber
    SELECT @P2itoAddressId = pta.P2iToAddressId
    FROM CoreParty.P2iToAddress AS pta
        INNER JOIN CoreParty.PartyToInitiator AS pti
            ON pti.PartyToInitiatorId = pta.fkPartyToInitiatorId
        INNER JOIN CoreInitiator.Initiator AS i
            ON i.InitiatorId = pti.fkInitiatorId
    WHERE i.InitiatorId IN
          (
              SELECT vck.InitiatorId
              FROM CoreParty.P2iToAddress AS pta
                  INNER JOIN CoreParty.PartyToInitiator AS pti
                      ON pti.PartyToInitiatorId = pta.fkPartyToInitiatorId
                  INNER JOIN dbo.vCaseKey AS vck
                      ON vck.InitiatorId = pti.fkInitiatorId
              WHERE pta.PtyPerNumberOld = @PerNumber
              GROUP BY vck.InitiatorId
              HAVING COUNT(1) > 1
          );

    -- insert the address ID and new pernumber into temp table
    INSERT INTO #TempP2itoAddressIds
    (
        P2itoAddressId
    )
    VALUES
    (@P2itoAddressId)

    -- remove the current pernumber from the temp table
    DELETE FROM #TempPersonNumbers
    WHERE PtyPerNumberOld = @PerNumber;
END;

-- ======================================================
-- Get the current maximum PtyPerNumberOld
-- ======================================================
SET @MaxPtyPerNumberOld =
(
    SELECT MAX(CAST(REPLACE(PtyPerNumberOld, '@', '0') AS BIGINT))
    FROM CoreParty.P2iToAddress (NOLOCK)
    WHERE PtyPerNumberOld IS NOT NULL
          AND PtyPerNumberOld LIKE '@%'
);

-- ======================================================
-- Set first 1500 of the records to null
-- ======================================================
UPDATE TOP (1500)
    CoreParty.P2iToAddress
SET PtyPerNumberOld = NULL
WHERE P2iToAddressId IN
        (
            SELECT  P2itoAddressId FROM #TempP2itoAddressIds
        );
 
-- ======================================================
-- ======================================================
BEGIN TRAN;

WHILE EXISTS (SELECT TOP 1 * FROM #TempP2itoAddressIds)
BEGIN
    SET @P2itoAddressId =
    (
        SELECT TOP 1 P2itoAddressId FROM #TempP2itoAddressIds
    );

    --Increment everytime you add a new entry
    SET @MaxPtyPerNumberOld = (@MaxPtyPerNumberOld + 1);

    UPDATE CoreParty.P2iToAddress
    SET PtyPerNumberOld =
        (
            SELECT '@' + RIGHT('00000000000' + CAST(@MaxPtyPerNumberOld AS VARCHAR(11)), 11)
        ),
        ModifiedDate = GETDATE()
    FROM CoreParty.P2iToAddress (NOLOCK)
    WHERE P2iToAddressId = @P2itoAddressId;

    UPDATE CoreParty.PartyToInitiator
    SET ModifiedDate = GETDATE()
    FROM CoreParty.PartyToInitiator
        INNER JOIN CoreParty.P2iToAddress
            ON PartyToInitiatorId = fkPartyToInitiatorId
    WHERE P2iToAddressId = @P2itoAddressId;

    DELETE FROM #TempP2itoAddressIds
    WHERE P2itoAddressId = @P2itoAddressId;
END;
COMMIT TRAN;

-- ======================================================
-- drop those temp tables
-- ======================================================
DROP TABLE #TempP2itoAddressIds;
DROP TABLE #TempPersonNumbers;
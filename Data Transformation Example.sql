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
-- ======================================================
SET @MaxPtyPerNumberOld =
(
    SELECT MAX(CAST(REPLACE(PtyPerNumberOld, '@', '0') AS BIGINT))
    FROM CoreParty.P2iToAddress (NOLOCK)
    WHERE PtyPerNumberOld IS NOT NULL
          AND PtyPerNumberOld LIKE '@%'
);


-- ======================================================
-- show current max pty per num old value
-- ======================================================
SELECT @MaxPtyPerNumberOld;

-- ======================================================
-- ======================================================
CREATE TABLE #TempP2itoAddressIds
(
    P2itoAddressId INT,
    PerNumber VARCHAR(16)
);


-- ======================================================
-- ======================================================
WHILE EXISTS (SELECT TOP 1 * FROM #TempPersonNumbers)
BEGIN
    -- get the next PerNumber from the temp table
    SET @PerNumber =
    (
        SELECT TOP (1) tpn.PtyPerNumberOld FROM #TempPersonNumbers AS tpn
    );

    -- increment the pernumber variable by 1
    SET @MaxPtyPerNumberOld = (@MaxPtyPerNumberOld + 1);

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
        P2itoAddressId,
        PerNumber
    )
    VALUES
    (@P2itoAddressId, @MaxPtyPerNumberOld);

    -- remove the current pernumber from the temp table
    DELETE FROM #TempPersonNumbers
    WHERE PtyPerNumberOld = @PerNumber;
END;

-- ======================================================
-- output what we would have updated
-- ======================================================
SELECT tpai.P2itoAddressId,
       tpai.PerNumber
FROM #TempP2itoAddressIds AS tpai;

-- ======================================================
-- drop those temp tables
-- ======================================================
DROP TABLE #TempP2itoAddressIds;
DROP TABLE #TempPersonNumbers;
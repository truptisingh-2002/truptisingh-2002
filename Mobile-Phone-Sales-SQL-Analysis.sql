SET NOCOUNT ON;
GO

/*=============================================================================
1. CREATE TABLES
=============================================================================*/

IF OBJECT_ID(N'dbo.MobilePhoneSales_Staging', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MobilePhoneSales_Staging
    (
        [Rank]                NVARCHAR(100) NULL,
        Manufacturer           NVARCHAR(200) NULL,
        Model                  NVARCHAR(300) NULL,
        [Form Factor]          NVARCHAR(200) NULL,
        [Smartphone Status]    NVARCHAR(100) NULL,
        [Year]                 NVARCHAR(100) NULL,
        [Units Sold]           NVARCHAR(100) NULL
    );
END;
GO

IF OBJECT_ID(N'dbo.MobilePhoneSales', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MobilePhoneSales
    (
        SalesID                INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_MobilePhoneSales PRIMARY KEY,
        [Rank]                 INT NULL,
        Manufacturer           NVARCHAR(100) NOT NULL,
        Model                  NVARCHAR(200) NOT NULL,
        [Form Factor]          NVARCHAR(100) NULL,
        [Smartphone Status]    NVARCHAR(20) NULL,
        [Year]                 INT NULL,
        [Units Sold]           DECIMAL(18,2) NULL,
        ImportedAt             DATETIME2(0) NOT NULL
            CONSTRAINT DF_MobilePhoneSales_ImportedAt DEFAULT SYSUTCDATETIME(),

        CONSTRAINT CK_MobilePhoneSales_Year
            CHECK ([Year] IS NULL OR [Year] BETWEEN 1900 AND 2100),
        CONSTRAINT CK_MobilePhoneSales_UnitsSold
            CHECK ([Units Sold] IS NULL OR [Units Sold] >= 0),
        CONSTRAINT CK_MobilePhoneSales_SmartphoneStatus
            CHECK ([Smartphone Status] IS NULL
                OR [Smartphone Status] IN (N'Yes', N'No', N'Unknown'))
    );
END;
GO

IF OBJECT_ID(N'dbo.MobilePhoneSalesAudit', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MobilePhoneSalesAudit
    (
        AuditID        BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_MobilePhoneSalesAudit PRIMARY KEY,
        SalesID        INT NOT NULL,
        Manufacturer   NVARCHAR(100) NOT NULL,
        Model          NVARCHAR(200) NOT NULL,
        OldUnitsSold   DECIMAL(18,2) NULL,
        NewUnitsSold   DECIMAL(18,2) NULL,
        ChangedAtUTC   DATETIME2(3) NOT NULL
            CONSTRAINT DF_MobilePhoneSalesAudit_ChangedAtUTC
            DEFAULT SYSUTCDATETIME(),
        ChangedBy      SYSNAME NOT NULL
            CONSTRAINT DF_MobilePhoneSalesAudit_ChangedBy
            DEFAULT SUSER_SNAME()
    );
END;
GO

/*=============================================================================
2. DATA VALIDATION AND LOAD
   Run after importing the CSV rows into dbo.MobilePhoneSales_Staging.
=============================================================================*/

-- Inspect raw staging rows before loading.
SELECT TOP (20) *
FROM dbo.MobilePhoneSales_Staging;

-- Validation summary: invalid numeric values and missing required text.
SELECT
    COUNT_BIG(*) AS StagingRowCount,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(Manufacturer)), N'') IS NULL
             THEN 1 ELSE 0 END) AS MissingManufacturer,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(Model)), N'') IS NULL
             THEN 1 ELSE 0 END) AS MissingModel,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM([Year])), N'') IS NOT NULL
                  AND TRY_CONVERT(INT, LTRIM(RTRIM([Year]))) IS NULL
             THEN 1 ELSE 0 END) AS InvalidYear,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM([Units Sold])), N'') IS NOT NULL
                  AND TRY_CONVERT(DECIMAL(18,2),
                      REPLACE(LTRIM(RTRIM([Units Sold])), N',', N'')) IS NULL
             THEN 1 ELSE 0 END) AS InvalidUnitsSold,
    SUM(CASE WHEN TRY_CONVERT(DECIMAL(18,2),
                      REPLACE(LTRIM(RTRIM([Units Sold])), N',', N'')) < 0
             THEN 1 ELSE 0 END) AS NegativeUnitsSold
FROM dbo.MobilePhoneSales_Staging;

-- Review rows with invalid year or units sold before loading.
SELECT *
FROM dbo.MobilePhoneSales_Staging
WHERE
    (NULLIF(LTRIM(RTRIM([Year])), N'') IS NOT NULL
     AND TRY_CONVERT(INT, LTRIM(RTRIM([Year]))) IS NULL)
 OR (NULLIF(LTRIM(RTRIM([Units Sold])), N'') IS NOT NULL
     AND TRY_CONVERT(DECIMAL(18,2),
         REPLACE(LTRIM(RTRIM([Units Sold])), N',', N'')) IS NULL);

-- Normalize smartphone status values into Yes / No / Unknown.
-- This load is append-only and avoids reloading exact duplicate source rows
-- by checking the full set of imported business columns.
-- If the source legitimately contains repeated identical records, review this
-- de-duplication rule before using it; remove the NOT EXISTS clause if needed.
INSERT INTO dbo.MobilePhoneSales
(
    [Rank], Manufacturer, Model, [Form Factor],
    [Smartphone Status], [Year], [Units Sold]
)
SELECT
    TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(s.[Rank])), N'')),
    LTRIM(RTRIM(s.Manufacturer)),
    LTRIM(RTRIM(s.Model)),
    NULLIF(LTRIM(RTRIM(s.[Form Factor])), N''),
    CASE
        WHEN UPPER(LTRIM(RTRIM(s.[Smartphone Status]))) IN
             (N'YES', N'Y', N'TRUE', N'1', N'SMARTPHONE')
            THEN N'Yes'
        WHEN UPPER(LTRIM(RTRIM(s.[Smartphone Status]))) IN
             (N'NO', N'N', N'FALSE', N'0', N'NON-SMARTPHONE',
              N'NON SMARTPHONE')
            THEN N'No'
        WHEN NULLIF(LTRIM(RTRIM(s.[Smartphone Status])), N'') IS NULL
            THEN N'Unknown'
        ELSE N'Unknown'
    END,
    TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(s.[Year])), N'')),
    TRY_CONVERT(DECIMAL(18,2),
        REPLACE(NULLIF(LTRIM(RTRIM(s.[Units Sold])), N''), N',', N''))
FROM dbo.MobilePhoneSales_Staging AS s
WHERE NULLIF(LTRIM(RTRIM(s.Manufacturer)), N'') IS NOT NULL
  AND NULLIF(LTRIM(RTRIM(s.Model)), N'') IS NOT NULL
  AND (NULLIF(LTRIM(RTRIM(s.[Year])), N'') IS NULL
       OR TRY_CONVERT(INT, LTRIM(RTRIM(s.[Year])) BETWEEN 1900 AND 2100)
       IS NOT NULL)
  AND (NULLIF(LTRIM(RTRIM(s.[Units Sold])), N'') IS NULL
       OR TRY_CONVERT(DECIMAL(18,2),
          REPLACE(LTRIM(RTRIM(s.[Units Sold])), N',', N'')) >= 0)
  AND NOT EXISTS
  (
      SELECT 1
      FROM dbo.MobilePhoneSales AS t
      WHERE ISNULL(t.[Rank], -2147483648) =
            ISNULL(TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(s.[Rank])), N'')),
                   -2147483648)
        AND t.Manufacturer = LTRIM(RTRIM(s.Manufacturer))
        AND t.Model = LTRIM(RTRIM(s.Model))
        AND ISNULL(t.[Form Factor], N'') =
            ISNULL(NULLIF(LTRIM(RTRIM(s.[Form Factor])), N''), N'')
        AND ISNULL(t.[Year], -2147483648) =
            ISNULL(TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(s.[Year])), N'')),
                   -2147483648)
        AND ISNULL(t.[Units Sold], -1) =
            ISNULL(TRY_CONVERT(DECIMAL(18,2),
                REPLACE(NULLIF(LTRIM(RTRIM(s.[Units Sold])), N''), N',', N'')),
                -1)
  );
GO

-- Confirm final table load.
SELECT
    COUNT_BIG(*) AS LoadedRecords,
    COUNT(DISTINCT Manufacturer) AS DistinctManufacturers,
    MIN([Year]) AS FirstYear,
    MAX([Year]) AS LastYear,
    SUM([Units Sold]) AS TotalUnitsSold
FROM dbo.MobilePhoneSales;
GO

/*=============================================================================
3. COMPLEX QUERIES
=============================================================================*/

-- Q1. Top 5 models by units sold in each year.
-- DENSE_RANK includes ties, so more than five rows may appear for a year.
WITH RankedModels AS
(
    SELECT
        [Year],
        Manufacturer,
        Model,
        [Units Sold],
        DENSE_RANK() OVER
        (
            PARTITION BY [Year]
            ORDER BY [Units Sold] DESC
        ) AS SalesRank
    FROM dbo.MobilePhoneSales
    WHERE [Year] IS NOT NULL
      AND [Units Sold] IS NOT NULL
)
SELECT
    [Year],
    SalesRank,
    Manufacturer,
    Model,
    [Units Sold]
FROM RankedModels
WHERE SalesRank <= 5
ORDER BY [Year] DESC, SalesRank, Manufacturer, Model;
GO

-- Q1 alternative: exactly five records per year (when at least five exist).
-- ROW_NUMBER requires deterministic tie-breakers.
WITH RankedModels AS
(
    SELECT
        [Year],
        Manufacturer,
        Model,
        [Units Sold],
        ROW_NUMBER() OVER
        (
            PARTITION BY [Year]
            ORDER BY [Units Sold] DESC, Manufacturer ASC, Model ASC, SalesID ASC
        ) AS RowNum
    FROM dbo.MobilePhoneSales
    WHERE [Year] IS NOT NULL
      AND [Units Sold] IS NOT NULL
)
SELECT [Year], RowNum, Manufacturer, Model, [Units Sold]
FROM RankedModels
WHERE RowNum <= 5
ORDER BY [Year] DESC, RowNum;
GO

-- Q2. Top 3 manufacturers by total units sold.
-- Ties are included by DENSE_RANK.
WITH ManufacturerTotals AS
(
    SELECT
        Manufacturer,
        SUM([Units Sold]) AS TotalUnitsSold
    FROM dbo.MobilePhoneSales
    WHERE [Units Sold] IS NOT NULL
    GROUP BY Manufacturer
),
RankedManufacturers AS
(
    SELECT
        Manufacturer,
        TotalUnitsSold,
        DENSE_RANK() OVER (ORDER BY TotalUnitsSold DESC) AS ManufacturerRank
    FROM ManufacturerTotals
)
SELECT ManufacturerRank, Manufacturer, TotalUnitsSold
FROM RankedManufacturers
WHERE ManufacturerRank <= 3
ORDER BY ManufacturerRank, Manufacturer;
GO

/*=============================================================================
4. USER-DEFINED FUNCTION AND WINDOW FUNCTIONS
=============================================================================*/

-- Q3. Scalar-valued function: average units sold for one manufacturer.
CREATE OR ALTER FUNCTION dbo.fn_AverageUnitsSold
(
    @Manufacturer NVARCHAR(100)
)
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @AverageUnitsSold DECIMAL(18,2);

    SELECT @AverageUnitsSold = AVG([Units Sold])
    FROM dbo.MobilePhoneSales
    WHERE Manufacturer = @Manufacturer
      AND [Units Sold] IS NOT NULL;

    RETURN @AverageUnitsSold;
END;
GO

-- Example function call. Change the manufacturer name as needed.
SELECT dbo.fn_AverageUnitsSold(N'Nokia') AS AverageUnitsSold;
GO

-- Average units sold for all manufacturers (more efficient for bulk reporting).
SELECT
    Manufacturer,
    AVG([Units Sold]) AS AverageUnitsSold
FROM dbo.MobilePhoneSales
GROUP BY Manufacturer
ORDER BY AverageUnitsSold DESC;
GO

-- Q4a. Three-row moving average per manufacturer.
-- This is a three-observation average, not necessarily three calendar years.
SELECT
    Manufacturer,
    [Year],
    Model,
    [Units Sold],
    AVG([Units Sold]) OVER
    (
        PARTITION BY Manufacturer
        ORDER BY [Year], SalesID
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS MovingAverage3Rows
FROM dbo.MobilePhoneSales
WHERE [Year] IS NOT NULL
  AND [Units Sold] IS NOT NULL
ORDER BY Manufacturer, [Year], SalesID;
GO

-- Q4b. Three-year moving average after aggregating to one row per
-- manufacturer per year. Missing years are not filled automatically.
WITH AnnualSales AS
(
    SELECT
        Manufacturer,
        [Year],
        SUM([Units Sold]) AS AnnualUnitsSold
    FROM dbo.MobilePhoneSales
    WHERE [Year] IS NOT NULL
      AND [Units Sold] IS NOT NULL
    GROUP BY Manufacturer, [Year]
)
SELECT
    Manufacturer,
    [Year],
    AnnualUnitsSold,
    AVG(AnnualUnitsSold) OVER
    (
        PARTITION BY Manufacturer
        ORDER BY [Year]
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS MovingAverage3Years
FROM AnnualSales
ORDER BY Manufacturer, [Year];
GO

/*=============================================================================
5. AUDIT TRIGGER
=============================================================================*/

-- The immutable SalesID primary key is used to match old/new versions safely.
CREATE OR ALTER TRIGGER dbo.trg_MobilePhoneSales_AuditUnitsSold
ON dbo.MobilePhoneSales
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.MobilePhoneSalesAudit
    (
        SalesID,
        Manufacturer,
        Model,
        OldUnitsSold,
        NewUnitsSold,
        ChangedAtUTC,
        ChangedBy
    )
    SELECT
        i.SalesID,
        i.Manufacturer,
        i.Model,
        d.[Units Sold],
        i.[Units Sold],
        SYSUTCDATETIME(),
        SUSER_SNAME()
    FROM inserted AS i
    INNER JOIN deleted AS d
        ON d.SalesID = i.SalesID
    WHERE
        i.[Units Sold] <> d.[Units Sold]
        OR (i.[Units Sold] IS NULL AND d.[Units Sold] IS NOT NULL)
        OR (i.[Units Sold] IS NOT NULL AND d.[Units Sold] IS NULL);
END;
GO

/*=============================================================================
6. SAFE TRIGGER TEST
   This test rolls back the data update. The audit insert is part of the same
   transaction and is therefore rolled back too. To inspect a persistent audit
   entry, perform a real update in a test database and COMMIT it.
=============================================================================*/

DECLARE @TestSalesID INT;

SELECT TOP (1) @TestSalesID = SalesID
FROM dbo.MobilePhoneSales
WHERE [Units Sold] IS NOT NULL
ORDER BY SalesID;

IF @TestSalesID IS NOT NULL
BEGIN
    BEGIN TRANSACTION;

    UPDATE dbo.MobilePhoneSales
    SET [Units Sold] = [Units Sold] + 1
    WHERE SalesID = @TestSalesID;

    -- Inspect the audit row generated inside this transaction.
    SELECT TOP (10) *
    FROM dbo.MobilePhoneSalesAudit
    WHERE SalesID = @TestSalesID
    ORDER BY AuditID DESC;

    ROLLBACK TRANSACTION;
END
ELSE
BEGIN
    PRINT 'Trigger test skipped: no row with a non-NULL Units Sold value exists.';
END;
GO

/*=============================================================================
7. ADDITIONAL QUALITY CHECKS AND SUMMARY
=============================================================================*/

-- Possible duplicate business records for review (not deleted automatically).
SELECT
    [Rank],
    Manufacturer,
    Model,
    [Form Factor],
    [Year],
    [Units Sold],
    COUNT(*) AS DuplicateCount
FROM dbo.MobilePhoneSales
GROUP BY
    [Rank], Manufacturer, Model, [Form Factor], [Year], [Units Sold]
HAVING COUNT(*) > 1
ORDER BY DuplicateCount DESC, Manufacturer, Model;

-- Sales summary by year.
SELECT
    [Year],
    SUM([Units Sold]) AS TotalUnitsSold,
    COUNT(*) AS RecordCount
FROM dbo.MobilePhoneSales
WHERE [Year] IS NOT NULL
GROUP BY [Year]
ORDER BY [Year];

-- Sales summary by form factor.
SELECT
    [Form Factor],
    SUM([Units Sold]) AS TotalUnitsSold,
    COUNT(*) AS RecordCount
FROM dbo.MobilePhoneSales
GROUP BY [Form Factor]
ORDER BY TotalUnitsSold DESC;

-- Sales summary by smartphone status.
SELECT
    [Smartphone Status],
    SUM([Units Sold]) AS TotalUnitsSold,
    COUNT(*) AS RecordCount
FROM dbo.MobilePhoneSales
GROUP BY [Smartphone Status]
ORDER BY TotalUnitsSold DESC;

-- Audit history (will be empty until a committed Units Sold update occurs).
SELECT TOP (100) *
FROM dbo.MobilePhoneSalesAudit
ORDER BY AuditID DESC;
GO


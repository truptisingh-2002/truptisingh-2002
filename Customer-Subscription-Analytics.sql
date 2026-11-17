
CREATE DATABASE AssessmentDB;
USE AssessmentDB
GO

-- QUESTION 1: Regional overdue ranking
DECLARE @AsOf DATE = '2026-08-31';

WITH Inv AS (
    SELECT c.Segment, c.Region, c.CustomerID, i.InvoiceAmount, i.DueDate,
           ISNULL((SELECT SUM(p.AmountPaid) FROM Payments p
                   WHERE p.InvoiceID = i.InvoiceID AND p.PaymentDate <= @AsOf), 0) AS Paid
    FROM Invoices i
    JOIN Subscriptions s ON s.SubscriptionID = i.SubscriptionID
    JOIN Customers c ON c.CustomerID = s.CustomerID
    WHERE I.InvoiceDate <= @AsOf
),
Totals AS (
    SELECT Segment, Region,
           COUNT(DISTINCT CustomerID) AS BilledCustomers,
           SUM(InvoiceAmount) AS InvoicedTotal,
           SUM(Paid) AS PaidTotal,
           SUM(InvoiceAmount - Paid) AS OutstandingTotal,
           SUM(CASE WHEN DueDate < @AsOf THEN InvoiceAmount - Paid ELSE 0 END) AS OverdueTotal
    FROM Inv
    GROUP BY Segment, Region
    HAVING COUNT(DISTINCT CustomerID) >= 5
)
SELECT *, DENSE_RANK() OVER (PARTITION BY Segment ORDER BY OverdueTotal DESC) AS OverdueRank
FROM Totals
ORDER BY Segment, OverdueRank;
GO

-- QUESTION 2: Billing streaks of 3+ consecutive months
WITH Months AS (
    SELECT DISTINCT s.CustomerID,
           DATEFROMPARTS(YEAR(i.InvoiceDate), MONTH(i.InvoiceDate), 1) AS MonthStart
    FROM Invoices i
    JOIN Subscriptions s ON s.SubscriptionID = i.SubscriptionID
    WHERE i.InvoiceDate >= '2025-01-01' AND i.InvoiceDate < '2027-01-01'
),
Islands AS (
    SELECT CustomerID, MonthStart,
           DATEADD(MONTH, -ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY MonthStart), MonthStart) AS IslandKey
    FROM Months
),
Streaks AS (
    SELECT CustomerID, MIN(MonthStart) AS StreakStart, MAX(MonthStart) AS StreakEnd, COUNT(*) AS MonthCount
    FROM Islands
    GROUP BY CustomerID, IslandKey
    HAVING COUNT(*) >= 3
)
SELECT st.CustomerID, st.StreakStart, st.StreakEnd, st.MonthCount,
       SUM(i.InvoiceAmount) AS InvoicedValue,
       COUNT(DISTINCT s.PlanID) AS DistinctPlans
FROM Streaks st
JOIN Subscriptions s ON s.CustomerID = st.CustomerID
JOIN Invoices i ON i.SubscriptionID = s.SubscriptionID
             AND i.InvoiceDate >= st.StreakStart
             AND i.InvoiceDate < DATEADD(MONTH, 1, st.StreakEnd)
GROUP BY st.CustomerID, st.StreakStart, st.StreakEnd, st.MonthCount
ORDER BY st.CustomerID, st.StreakStart;
GO

-- QUESTION 3: Unpaid balances and support risk
DECLARE @AsOf DATE = '2026-08-31';
DECLARE @Start DATETIME2 = '2026-06-02';   -- 90 days before cutoff
DECLARE @End DATETIME2 = '2026-09-01';     -- end of 31 Aug

WITH Balance AS (
    SELECT s.CustomerID,
           SUM(i.InvoiceAmount - ISNULL((SELECT SUM(p.AmountPaid) FROM Payments p
                   WHERE p.InvoiceID = i.InvoiceID AND p.PaymentDate <= @AsOf), 0)) AS UnpaidBalance
    FROM Invoices i
    JOIN Subscriptions s ON s.SubscriptionID = i.SubscriptionID
    WHERE i.InvoiceDate <= @AsOf
    GROUP BY s.CustomerID
),
Tickets AS (
    SELECT CustomerID,
           COUNT(*) AS HighCriticalTickets,
           SUM(CASE WHEN ClosedAt IS NULL OR ClosedAt >= @End THEN 1 ELSE 0 END) AS StillOpen,
           AVG(CASE WHEN ClosedAt < @End THEN DATEDIFF(MINUTE, OpenedAt, ClosedAt) / 60.0 END) AS AvgResolutionHours
    FROM SupportTickets
    WHERE Priority IN ('High', 'Critical') AND OpenedAt >= @Start AND OpenedAt < @End
    GROUP BY CustomerID
    HAVING COUNT(*) >= 2
)
SELECT TOP (10) WITH TIES
       b.CustomerID, b.UnpaidBalance, t.HighCriticalTickets, t.StillOpen, t.AvgResolutionHours
FROM Balance b
JOIN Tickets t ON t.CustomerID = b.CustomerID
WHERE b.UnpaidBalance > 0
ORDER BY b.UnpaidBalance DESC;

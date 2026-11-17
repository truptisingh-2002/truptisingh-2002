-- SQL Server (MSSQL) assessment schema. Import matching CSV files via SSMS > Tasks > Import Flat File or BULK INSERT.
-- Blank cells in nullable date fields must be loaded as NULL.
CREATE TABLE Customers (CustomerID INT PRIMARY KEY,Segment VARCHAR(30),Region VARCHAR(20),SignupDate DATE);
CREATE TABLE Plans (PlanID INT PRIMARY KEY,PlanName VARCHAR(30),MonthlyFee DECIMAL(12,2));
CREATE TABLE Subscriptions (SubscriptionID INT PRIMARY KEY,CustomerID INT REFERENCES Customers(CustomerID),PlanID INT REFERENCES Plans(PlanID),StartDate DATE,EndDate DATE NULL,Status VARCHAR(20));
CREATE TABLE Invoices (InvoiceID INT PRIMARY KEY,SubscriptionID INT REFERENCES Subscriptions(SubscriptionID),InvoiceDate DATE,DueDate DATE,InvoiceAmount DECIMAL(12,2));
CREATE TABLE Payments (PaymentID INT PRIMARY KEY,InvoiceID INT REFERENCES Invoices(InvoiceID),PaymentDate DATE,AmountPaid DECIMAL(12,2),PaymentMethod VARCHAR(20));
CREATE TABLE SupportTickets (TicketID INT PRIMARY KEY,CustomerID INT REFERENCES Customers(CustomerID),OpenedAt DATETIME2,ClosedAt DATETIME2 NULL,Priority VARCHAR(20),Category VARCHAR(20));
-- Load order: Customers, Plans, Subscriptions, Invoices, Payments, SupportTickets.

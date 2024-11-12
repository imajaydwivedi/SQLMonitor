use tempdb
go

CREATE TABLE dbo.Orders
(
    OrderId INT NOT NULL,
    OrderNum VARCHAR(32) NOT NULL,
    OrderDate SMALLDATETIME NOT NULL,
    CustomerId INT NOT NULL,
    Amount MONEY NOT NULL,
    OrderStatus INT NOT NULL,
    Placeholder CHAR(400) NULL
);
go

;WITH N1(C) AS (SELECT 0 UNION ALL SELECT 0) -- 2 rows
,N2(C) AS (SELECT 0 FROM N1 AS T1 CROSS JOIN N1 AS T2) -- 4 rows
,N3(C) AS (SELECT 0 FROM N2 AS T1 CROSS JOIN N2 AS T2) -- 16 rows
,N4(C) AS (SELECT 0 FROM N3 AS T1 CROSS JOIN N3 AS T3) -- 256 rows
,N5(C) AS (SELECT 0 FROM N4 AS T1 CROSS JOIN N4) -- 65,536 rows
,IDs(ID) AS (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM N5)
INSERT INTO dbo.Orders(OrderId,OrderNum,OrderDate,CustomerId,Amount,OrderStatus)
    SELECT 
        ID,CONVERT(VARCHAR(32),ID),DATEADD(DAY,-ID % 365,GETDATE())
        ,ID % 512,ID % 100,0
    FROM 
        IDs; 
go

CREATE UNIQUE CLUSTERED INDEX IDX_Orders_OrderId
ON dbo.Orders(OrderId);
go

/*	Blocking Scenario: Session 01
begin tran
	delete from dbo.Orders
	where OrderId = 50;

	waitfor delay '02:00:00'
rollback tran

*/

/*	Blocking Scenario: Session 02
use tempdb
go

select OrderId, Amount
from dbo.Orders with (readcommittedlock)
where OrderNum = 100

*/

/*	Deadlock Scenario: Session 01
begin tran
	-- 1
	update dbo.Orders set OrderStatus = 1
		where OrderId = 10;

	-- 3
	select count(*) as [Cnt]
		from dbo.Orders with (readcommittedlock)
		where CustomerId = 42;
commit
*/

/*	Deadlock Scenario: Session 02
begin tran
	-- 2
	update dbo.Orders set OrderStatus = 1
		where OrderId = 250;

	-- 4
	select count(*) as [Cnt]
		from dbo.Orders with (readcommittedlock)
		where CustomerId = 18;
commit
*/
-- （1） 查询读者 Rose 借过的读书（包括已还和未还）的图书号、书名和借阅日期；
SELECT Book.bid, Book.bname, Borrow.borrow_Date
FROM Borrow, Reader, Book
WHERE Reader.rname = 'Rose'
AND Borrow.book_ID = Book.bid
AND Borrow.reader_ID = Reader.rid;

-- （2） 查询从没有借过图书也从没有预约过图书的读者号和读者姓名； 
SELECT rid, rname
FROM reader
where rid not in (select distinct reader_ID from borrow);

-- （3） 查询被借阅次数最多的作者（注意一个作者可能写了多本书）
-- （两种方法： A.使用borrow表中的借阅记录； B.使用book表中的borrow_times） 
select Book.author, COUNT(*) as borrow_count
from book, borrow
where book.bid = borrow.book_ID
group by book.author
order by borrow_count desc
limit 1;

-- （4） 查询目前借阅未还的书名中包含“MySQL”的图书号和书名； 
select book.bid, book.bname
from book, borrow
where book.bid = borrow.book_ID
and borrow.return_Date is null 
and book.bname like '%MySQL%';

-- （5） 查询历史借阅图书数目超过 3 本的读者姓名；
select reader.rname, count(*) as borrow_count
from reader, borrow
where borrow.reader_ID = reader.rid
group by reader.rid having count(*) > 3;

-- （6） 查询没有借阅过任何一本 J.K. Rowling 所著的图书的读者号和姓名；
select rid, rname
from reader
where rid not in (
select borrow.reader_ID
from borrow, book
where borrow.book_ID = book.bid
AND book.author = 'J.K. Rowling'
);

-- （7） 查询 2024 年借阅图书数目排名前 3 名（可并列）的读者号、姓名以及借阅图书数；
-- select reader.rid, reader.rname, count(*) as borrow_count
-- from reader, borrow
-- where reader.rid = borrow.reader_ID
-- and year(borrow.borrow_Date) = 2024
-- group by reader.rid
-- order by borrow_count desc
-- limit 3;

SELECT reader.rid, reader.rname, COUNT(*) AS borrow_count
FROM reader, borrow
WHERE reader.rid = borrow.reader_ID
  AND YEAR(borrow.borrow_Date) = 2024
GROUP BY reader.rid
HAVING borrow_count >= (
    SELECT DISTINCT COUNT(*)
    FROM reader, borrow
    WHERE reader.rid = borrow.reader_ID
      AND YEAR(borrow.borrow_Date) = 2024
    GROUP BY reader.rid
    ORDER BY COUNT(*) DESC
    LIMIT 1 OFFSET 2
)
ORDER BY borrow_count DESC;

/*（8） 创建一个读者借书信息的视图，该视图包含读者号、姓名、所借图书号、
图书名和借阅日期；并使用该视图查询2024年所有读者的读者号以及所借
阅的不同图书数；*/
DROP VIEW IF EXISTS ReaderBorrow_view;
-- 创建视图
create view ReaderBorrow_view (rid, rname, bid, bname, borrow_Date)
as select reader.rid, reader.rname, book.bid, book.bname, borrow.borrow_Date
from reader, book, borrow
where reader.rid = borrow.reader_ID
and book.bid = borrow.book_ID;

-- 使用视图查询2024年所有读者的读者号以及所借阅的不同图书数
select rid, count(distinct bid) AS distinct_book_count
from ReaderBorrow_view
where year(borrow_Date) = 2024
group by rid;







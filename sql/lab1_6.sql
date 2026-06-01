
USE `db_lab1`;
DROP TRIGGER IF EXISTS after_reserve_insert;
DROP TRIGGER IF EXISTS after_reserve_delete;

USE `db_lab1`$$
DELIMITER $$

-- 触发器A：预约时修改图书状态和增加reserve_Times
CREATE TRIGGER after_reserve_insert
AFTER INSERT ON Reserve
FOR EACH ROW
BEGIN
    DECLARE v_book_status INT;
    
    -- 检查图书是否被借出
    SELECT bstatus INTO v_book_status
    FROM Book
    WHERE bid = NEW.book_ID;
    
    -- 如果没有被借出，状态改为2（已被预约）
    IF v_book_status != 1 THEN
        UPDATE Book SET bstatus = 2 WHERE bid = NEW.book_ID;
    END IF;
    
    -- 增加预约人数
    UPDATE Book SET reserve_Times = reserve_Times + 1 WHERE bid = NEW.book_ID;
END$$

-- 触发器B：预约书被借出或取消时减少reserve_Times
CREATE TRIGGER after_reserve_delete
AFTER DELETE ON Reserve
FOR EACH ROW
BEGIN
	DECLARE v_book_status INT;
    DECLARE v_book_reserve_times INT;
    DECLARE v_borrow_exists INT;
    UPDATE Book SET reserve_Times = reserve_Times - 1 WHERE bid = OLD.book_ID;
    
    SELECT bstatus, reserve_Times INTO v_book_status, v_book_reserve_times
    FROM Book
    WHERE bid = OLD.book_ID;
    
	-- 检查是否有借阅记录
    SELECT COUNT(*) INTO v_borrow_exists
    FROM Borrow
    WHERE book_ID = OLD.book_ID 
      AND return_Date IS NULL;
    
    IF v_book_reserve_times = 0 AND v_borrow_exists > 0 THEN -- 当前已被借阅
		UPDATE Book SET bstatus = 1 WHERE bid = OLD.book_ID;
    ELSEIF v_book_reserve_times = 0 AND v_borrow_exists = 0 THEN -- 当前未被借阅
		UPDATE Book SET bstatus = 0 WHERE bid = OLD.book_ID;
	END IF;

END$$

DELIMITER ;
-- 测试 
SELECT *FROM book WHERE bid = 'B007';

INSERT INTO reserve(book_ID, reader_ID, reserve_Date, take_Date)
	VALUES('B007', 'R001', CURDATE(), NULL);

SELECT *FROM book WHERE bid = 'B007';
DELETE FROM Reserve WHERE book_ID = 'B007' AND reader_ID = 'R001';

SELECT *FROM book WHERE bid = 'B007';

USE `db_lab1`;
DROP procedure IF EXISTS returnBook;

DELIMITER $$
USE `db_lab1`$$
CREATE PROCEDURE returnBook(
    IN p_reader_ID CHAR(8),
    IN p_book_ID CHAR(8)
)
BEGIN
    DECLARE v_borrow_exists INT; -- 是否借阅
    DECLARE v_reserve_count INT; -- 预约数量
    
    DECLARE s INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET s = 1;
    
    START TRANSACTION;
    
    -- 检查是否有借阅记录
    SELECT COUNT(*) INTO v_borrow_exists
    FROM Borrow
    WHERE reader_ID = p_reader_ID 
      AND book_ID = p_book_ID 
      AND return_Date IS NULL;
    
    IF v_borrow_exists = 0 THEN
        SELECT '还书失败：没有找到该读者的未还借阅记录' AS message;
        SET s = 2;
    END IF;
    
    -- A. 更新借阅记录的 return_Date
    UPDATE Borrow 
    SET return_Date = CURDATE()
    WHERE reader_ID = p_reader_ID 
      AND book_ID = p_book_ID 
      AND return_Date IS NULL;
    
    -- 检查该书是否有其他预约
    SELECT COUNT(*) INTO v_reserve_count
    FROM Reserve
    WHERE book_ID = p_book_ID;
    
    -- B. 更新图书状态：有预约则设为2，否则设为0
    IF v_reserve_count > 0 THEN
        UPDATE Book SET bstatus = 2 WHERE bid = p_book_ID;
    ELSE
        UPDATE Book SET bstatus = 0 WHERE bid = p_book_ID;
    END IF;
    
    IF s = 0 THEN
		SELECT '还书成功' AS message;
        COMMIT;    -- 成功
    ELSE
        ROLLBACK; -- 失败
    END IF;
    
    
END$$

DELIMITER ;

-- 测试调用
CALL returnBook('R001', 'B008');  -- 未借阅，应失败

SELECT *FROM Borrow WHERE reader_ID = 'R001' AND book_ID = 'B001';
SELECT *FROM Book WHERE bid = 'B001';
CALL returnBook('R001', 'B001');  -- 正常还书

SELECT *FROM Borrow WHERE reader_ID = 'R001' AND book_ID = 'B001';
SELECT *FROM Book WHERE bid = 'B001';



USE `db_lab1`;
DROP procedure IF EXISTS borrowBook;

DELIMITER $$
USE `db_lab1`$$
CREATE PROCEDURE borrowBook(
    IN p_reader_ID CHAR(8),
    IN p_book_ID CHAR(8)
)
BEGIN
    DECLARE v_borrow_count INT; -- 已借未还图书数量
    DECLARE v_today_borrow INT; -- 今天借阅本数
    -- DECLARE v_reserve_count INT; 
    DECLARE v_has_reservation INT; -- 已经预约
    DECLARE v_book_status INT; -- 图书状态
    
    DECLARE s INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET s = 1;
    
    START TRANSACTION;
    
    
    -- A. 检查同一天是否重复借阅同一本书
    SELECT COUNT(*) INTO v_today_borrow
    FROM Borrow
    WHERE reader_ID = p_reader_ID 
      AND book_ID = p_book_ID 
      AND borrow_Date = CURDATE();
    
    IF v_today_borrow > 0 THEN
        SELECT '借阅失败：同一天不能重复借阅同一本书' AS message;
        SET s = 2;
    END IF;
    
    -- B. 如果有预约记录，当前借阅者没有预约则不允许借阅    
    -- 获取图书状态
    SELECT bstatus INTO v_book_status 
    FROM Book 
    WHERE bid = p_book_ID;
    
    
    -- 检查当前读者是否有预约
    SELECT COUNT(*) INTO v_has_reservation
    FROM Reserve
    WHERE book_ID = p_book_ID AND reader_ID = p_reader_ID;
    
    IF v_book_status = 2 AND v_has_reservation = 0 AND s = 0 THEN
        SELECT '借阅失败：该书已被预约，只有预约者才能借阅' AS message;
        SET s = 3;
    END IF;
    
	-- C. 检查读者已借未还图书数量（最多3本）
    SELECT COUNT(*) INTO v_borrow_count
    FROM Borrow
    WHERE reader_ID = p_reader_ID AND return_Date IS NULL;
    
    IF v_borrow_count >= 3 AND s = 0 THEN
        SELECT '借阅失败：已借阅3本图书，请先归还' AS message;
        SET s = 4;
    END IF;
    
    IF v_book_status = 1 AND s = 0 THEN
        SELECT '借阅失败：该书已被借阅' AS message;
        SET s = 5;
    END IF;

    -- D. 如果有预约记录且当前读者有预约，删除该预约记录
    IF v_has_reservation > 0 THEN
        DELETE FROM Reserve WHERE book_ID = p_book_ID AND reader_ID = p_reader_ID;
    END IF;
    
    -- 插入借阅记录
	INSERT INTO Borrow(book_ID, reader_ID, borrow_Date, return_Date)
	VALUES(p_book_ID, p_reader_ID, CURDATE(), NULL);
    
    -- E. 借阅成功后图书表的 borrow_Times 加1
    UPDATE Book SET borrow_Times = borrow_Times + 1 WHERE bid = p_book_ID;
    
    -- F. 借阅成功后修改 bstatus
    UPDATE Book SET bstatus = 1 WHERE bid = p_book_ID;
    
	IF s = 0 THEN
		SELECT '借阅成功' AS message;
        COMMIT;    -- 成功
    ELSE
        ROLLBACK; -- 失败
    END IF;
    
    
END$$

DELIMITER ;

-- 测试调用
CALL borrowBook('R001', 'B008');  -- 未预约，应失败

SELECT *FROM Borrow WHERE reader_ID = 'R001' AND book_ID = 'B006';
SELECT *FROM Reserve WHERE reader_ID = 'R001' AND book_ID = 'B006';
SELECT *FROM Book WHERE bid = 'B006';

CALL borrowBook('R001', 'B006');  -- 已预约，应成功

SELECT *FROM Borrow WHERE reader_ID = 'R001' AND book_ID = 'B006';
SELECT *FROM Reserve WHERE reader_ID = 'R001' AND book_ID = 'B006';
SELECT *FROM Book WHERE bid = 'B006';

CALL borrowBook('R001', 'B006');  -- 同一天重复，应失败
CALL borrowBook('R001', 'B007');  -- 已借3本，应失败
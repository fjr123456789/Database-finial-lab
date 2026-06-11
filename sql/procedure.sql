USE `finial_lab`;

-- =====================================================
-- 函数：计算指定借阅记录的逾期天数
-- =====================================================
DROP FUNCTION IF EXISTS `CalculateOverdueDays`;
DELIMITER //

CREATE FUNCTION `CalculateOverdueDays`(p_borrow_id INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_borrow_date DATE;
    DECLARE v_return_date DATE;
    DECLARE v_overdue_days INT;
    
    -- 获取借阅信息
    SELECT borrow_date, return_date INTO v_borrow_date, v_return_date
    FROM borrow_record WHERE record_id = p_borrow_id;
    
    -- 如果已归还，逾期天数 = 归还日期 - 应还日期
    IF v_return_date IS NOT NULL THEN
        SET v_overdue_days = GREATEST(0, DATEDIFF(v_return_date, DATE_ADD(v_borrow_date, INTERVAL 30 DAY)));
    ELSE
        -- 如果未归还，逾期天数 = 今天 - 应还日期
        SET v_overdue_days = GREATEST(0, DATEDIFF(CURDATE(), DATE_ADD(v_borrow_date, INTERVAL 30 DAY)));
    END IF;
    
    RETURN v_overdue_days;
END//

DELIMITER ;


-- =====================================================
-- 函数：计算指定借阅记录的逾期罚款金额
-- =====================================================
DROP FUNCTION IF EXISTS `CalculateFineAmount`;
DELIMITER //

CREATE FUNCTION `CalculateFineAmount`(p_borrow_id INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_overdue_days INT;
    
    SET v_overdue_days = CalculateOverdueDays(p_borrow_id);
    
    RETURN v_overdue_days * 0.1;
END//

DELIMITER ;


-- =====================================================
-- 函数：查询学生总罚款（从逾期记录表计算）
-- =====================================================
DROP FUNCTION IF EXISTS `GetStudentTotalFine`;
DELIMITER //

CREATE FUNCTION `GetStudentTotalFine`(p_student_id VARCHAR(20))
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE total DECIMAL(10,2);
    
	SELECT IFNULL(SUM(CalculateFineAmount(o.borrow_id)), 0) INTO total
	FROM overdue_record o, borrow_record b
	WHERE o.borrow_id = b.record_id
	  AND b.student_id = p_student_id 
	  AND o.paid_status = FALSE;
    
    RETURN total;
END//

DELIMITER ;


-- 创建逾期记录视图（包含计算字段）
DROP VIEW IF EXISTS `overdue_record_view`;
CREATE VIEW `overdue_record_view` AS
SELECT 
    o.overdue_id,
    o.borrow_id,
    o.paid_status,
    o.paid_date,
    b.student_id,
    s.name AS student_name,
    b.book_id,
    bk.title AS book_title,
    b.borrow_date,
    b.return_date,
    DATE_ADD(b.borrow_date, INTERVAL 30 DAY) AS due_date,
    CalculateOverdueDays(b.record_id) AS overdue_days,
    CalculateFineAmount(b.record_id) AS fine_amount
FROM 
    overdue_record o,
    borrow_record b,
    student s,
    book bk
WHERE 
    o.borrow_id = b.record_id
    AND b.student_id = s.student_id
    AND b.book_id = bk.book_id;


-- =====================================================
-- 借阅记录视图
-- =====================================================
DROP VIEW IF EXISTS `borrow_record_view`;
CREATE VIEW `borrow_record_view` AS
SELECT 
    br.record_id,
    br.student_id,
    s.name AS student_name,
    br.book_id,
    bk.title AS book_title,
    br.borrow_date,
    br.return_date,
    -- 计算应还日期（借书日期 + 30天）
    DATE_ADD(br.borrow_date, INTERVAL 30 DAY) AS due_date,
    -- 计算状态
    CASE 
        WHEN br.return_date IS NOT NULL THEN '已还'
        WHEN DATE_ADD(br.borrow_date, INTERVAL 30 DAY) < CURDATE() THEN '逾期'
        ELSE '借阅中'
    END AS status
FROM 
    borrow_record br,
    student s,
    book bk
WHERE 
    br.student_id = s.student_id
    AND br.book_id = bk.book_id;

-- =====================================================
-- 存储过程：还书处理
-- =====================================================
DROP PROCEDURE IF EXISTS `ReturnBook`;
DELIMITER //

CREATE PROCEDURE `ReturnBook`(
    IN p_record_id INT,
    OUT p_state INT,
    OUT p_message VARCHAR(100)
)
BEGIN
    DECLARE v_borrow_date DATE;
    DECLARE v_due_date DATE;
    DECLARE v_student_id VARCHAR(20);
    DECLARE v_book_id VARCHAR(20);
    DECLARE v_return_date DATE;
    DECLARE v_overdue_days INT;
    DECLARE v_fine DECIMAL(10,2);
    DECLARE v_record_exists INT;
    DECLARE v_today DATE;
    
    -- 错误处理
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_state = 3;
        SET p_message = '系统错误，还书失败';
    END;
    
    SET v_today = CURDATE();
    SET p_state = 0;
    SET p_message = '';
    
    START TRANSACTION;
    
    -- 1. 查询借阅记录
    SELECT COUNT(*) INTO v_record_exists
    FROM borrow_record WHERE record_id = p_record_id;
    
    IF v_record_exists = 0 THEN
        SET p_state = 1;
        SET p_message = '借阅记录不存在';
        ROLLBACK;
    ELSE
        -- 获取借阅信息
        SELECT borrow_date, return_date, student_id, book_id 
        INTO v_borrow_date, v_return_date, v_student_id, v_book_id
        FROM borrow_record WHERE record_id = p_record_id;
        
        -- 2. 检查是否已归还
        IF v_return_date IS NOT NULL THEN
            SET p_state = 2;
            SET p_message = '该书已经归还过了';
            ROLLBACK;
        ELSE
            -- 3. 更新借阅记录
            UPDATE borrow_record 
            SET return_date = v_today
            WHERE record_id = p_record_id;
            
--             -- 4. 更新图书可借数量
--             UPDATE book SET available_count = available_count + 1
--             WHERE book_id = v_book_id;
            
            -- 5. 计算应还日期和逾期罚款
            SET v_due_date = DATE_ADD(v_borrow_date, INTERVAL 30 DAY);
            
            IF v_today > v_due_date THEN
               SET v_overdue_days = DATEDIFF(v_today, v_due_date);
               SET v_fine = v_overdue_days * 0.1; 
                
                SET p_message = CONCAT('还书成功，逾期', v_overdue_days, '天，罚款', v_fine, '元');
            ELSE
                SET p_message = '还书成功，无逾期';
            END IF;
            
            SET p_state = 0;
            COMMIT;
        END IF;
    END IF;
END//

DELIMITER ;


DROP PROCEDURE IF EXISTS `BorrowBook`;
DELIMITER $$

CREATE PROCEDURE `BorrowBook`(
    IN p_student_id VARCHAR(20),
    IN p_book_id VARCHAR(20),
    OUT p_state INT,
    OUT p_message VARCHAR(200)
)
BEGIN
    DECLARE v_book_count INT;
    DECLARE v_borrow_count INT;
    DECLARE v_overdue_exists INT;
    DECLARE v_book_title VARCHAR(200);
    DECLARE v_today DATE;
    DECLARE v_has_reservation INT;    -- 是否有预约
    
    DECLARE s INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET s = 1;
    
    SET v_today = CURDATE();
    SET p_state = 0;
    SET p_message = '';
    
    START TRANSACTION;
    
    -- 1. 检查图书是否存在且可借
    SELECT available_count, title INTO v_book_count, v_book_title
    FROM book 
    WHERE book_id = p_book_id;
    
    IF v_book_count IS NULL THEN
        SET p_state = 1;
        SET p_message = '图书不存在';
        SET s = 1;
    ELSEIF v_book_count <= 0 THEN
        SET p_state = 2;
        SET p_message = '该书已借完';
        SET s = 1;
    END IF;
    
    -- 2. 检查是否有逾期未还
    IF s = 0 THEN
        SELECT COUNT(*) INTO v_overdue_exists
        FROM borrow_record br
        WHERE br.student_id = p_student_id
          AND br.return_date IS NULL
          AND DATE_ADD(br.borrow_date, INTERVAL 30 DAY) < v_today;
        
        IF v_overdue_exists > 0 THEN
            SET p_state = 3;
            SET p_message = '请先还清逾期图书';
            SET s = 1;
        END IF;
    END IF;
    
    -- 3. 检查借阅数量（最多5本）
    IF s = 0 THEN
        SELECT COUNT(*) INTO v_borrow_count
        FROM borrow_record
        WHERE student_id = p_student_id
          AND return_date IS NULL;
        
        IF v_borrow_count >= 5 THEN
            SET p_state = 4;
            SET p_message = '借书数量已达上限（5本）';
            SET s = 1;
        END IF;
    END IF;
    
    -- 4. 检查预约情况（如果图书已被预约，只有预约者才能借阅）
    IF s = 0 THEN
        -- 检查图书是否有等待中的预约
        SELECT COUNT(*) INTO v_has_reservation
        FROM reservation_record
        WHERE book_id = p_book_id 
          AND status = '等待中';
        
        IF v_has_reservation > 0 THEN
            -- 检查当前读者是否有预约
            SELECT COUNT(*) INTO v_has_reservation
            FROM reservation_record
            WHERE book_id = p_book_id 
              AND student_id = p_student_id 
              AND status = '等待中';
            
            IF v_has_reservation = 0 THEN
                SET p_state = 6;
                SET p_message = '借阅失败：该书已被预约，只有预约者才能借阅';
                SET s = 1;
            END IF;
        END IF;
    END IF;
    
    -- 5. 执行借阅操作
    IF s = 0 THEN
        -- 创建借阅记录
        INSERT INTO borrow_record (student_id, book_id, borrow_date, return_date)
        VALUES (p_student_id, p_book_id, v_today, NULL);
        
-- 		UPDATE book SET available_count = available_count - 1
-- 		WHERE book_id = book_id;
        
        -- 如果当前读者有预约，更新该预约记录
        UPDATE reservation_record SET status = '已取书'
        WHERE student_id = p_student_id 
          AND book_id = p_book_id 
          AND status = '等待中';
        
        SET p_state = 0;
        SET p_message = CONCAT('成功借阅《', v_book_title, '》');
        
        COMMIT;
    ELSE
        ROLLBACK;
    END IF;
END$$

DELIMITER ;

-- CALL BorrowBook('001', 'B010', @state, @message);
-- SELECT @state, @message;

-- =====================================================
-- 检查是否逾期
-- =====================================================
DROP PROCEDURE IF EXISTS `GenerateDailyOverdue`;
DELIMITER //

CREATE PROCEDURE `GenerateDailyOverdue`()
BEGIN
    -- 插入新的逾期记录（只插入未记录过的）
    INSERT INTO overdue_record (borrow_id, paid_status)
    SELECT 
        br.record_id,
        FALSE
    FROM borrow_record br
    WHERE br.return_date IS NULL
      AND DATE_ADD(br.borrow_date, INTERVAL 30 DAY) < CURDATE()
      AND NOT EXISTS (
          SELECT 1 FROM overdue_record o 
          WHERE o.borrow_id = br.record_id
      );
END//

DELIMITER ;

-- CALL ReturnBook(4, @state, @message);
-- SELECT @state, @message;
USE `finial_lab`;

-- =====================================================
-- 函数1：计算指定借阅记录的逾期天数
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
-- 函数2：计算指定借阅记录的逾期罚款金额
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
    
    RETURN v_overdue_days * 0.5;
END//

DELIMITER ;


-- =====================================================
-- 函数3：查询学生总罚款（从逾期记录表计算）
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
    FROM overdue_record o
    JOIN borrow_record b ON o.borrow_id = b.record_id
    WHERE b.student_id = p_student_id AND o.paid_status = FALSE;
    
    RETURN total;
END//

DELIMITER ;


-- =====================================================
-- 函数4：查询学生的逾期记录列表
-- =====================================================
DROP FUNCTION IF EXISTS `GetStudentOverdueInfo`;
DELIMITER //

CREATE FUNCTION `GetStudentOverdueInfo`(p_borrow_id INT)
RETURNS VARCHAR(200)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_overdue_days INT;
    DECLARE v_fine DECIMAL(10,2);
    DECLARE v_result VARCHAR(200);
    
    SET v_overdue_days = CalculateOverdueDays(p_borrow_id);
    SET v_fine = CalculateFineAmount(p_borrow_id);
    
    IF v_overdue_days > 0 THEN
        SET v_result = CONCAT('逾期', v_overdue_days, '天，罚款', v_fine, '元');
    ELSE
        SET v_result = '无逾期';
    END IF;
    
    RETURN v_result;
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
FROM overdue_record o
JOIN borrow_record b ON o.borrow_id = b.record_id
JOIN student s ON b.student_id = s.student_id
JOIN book bk ON b.book_id = bk.book_id;


-- =====================================================
-- 8. 存储过程：还书处理（带事务控制和错误处理）
-- 不使用 status 字段，通过 return_date 判断是否已还
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
    DECLARE v_book_exists INT;
    
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
            
            -- 4. 更新图书可借数量
            UPDATE book SET available_count = available_count + 1
            WHERE book_id = v_book_id;
            
            -- 5. 计算应还日期和逾期罚款
            SET v_due_date = DATE_ADD(v_borrow_date, INTERVAL 30 DAY);
            
            IF v_today > v_due_date THEN
               --  SET v_overdue_days = DATEDIFF(v_today, v_due_date);
--                 SET v_fine = v_overdue_days * 0.5;
--                 
--                 INSERT INTO overdue_record(borrow_id, student_id, overdue_days, fine_amount, paid_status)
--                 VALUES(p_record_id, v_student_id, v_overdue_days, v_fine, FALSE);
                
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
USE `finial_lab`;
-- =====================================================
-- 8. 存储过程：还书处理（带事务控制和错误处理）
-- =====================================================
DROP PROCEDURE IF EXISTS `ReturnBook`;
DELIMITER //
CREATE PROCEDURE `ReturnBook`(
    IN p_record_id INT,
    IN p_return_date DATE,
    OUT p_state INT,           -- 输出状态：0=成功，1=记录不存在，2=已归还，3=其他错误
    OUT p_message VARCHAR(100) -- 输出消息
)
BEGIN
    DECLARE v_due_date DATE;
    DECLARE v_student_id VARCHAR(20);
    DECLARE v_book_id VARCHAR(20);
    DECLARE v_overdue_days INT;
    DECLARE v_fine DECIMAL(10,2);
    DECLARE v_current_status VARCHAR(20);
    DECLARE v_record_exists INT;
    
    -- 错误处理变量
    DECLARE s INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET s = 1;
    
    -- 初始化输出参数
    SET p_state = 0;
    SET p_message = '';
    
    -- 开始事务
    START TRANSACTION;
    
    -- ========== 1. 验证借阅记录是否存在 ==========
    SELECT COUNT(*) INTO v_record_exists 
    FROM borrow_record WHERE record_id = p_record_id;
    
    IF v_record_exists = 0 THEN
        SET p_state = 1;
        SET p_message = '借阅记录不存在';
        SET s = 2;  -- 标记为业务错误
    END IF;
    
    -- ========== 2. 检查是否已经归还 ==========
    IF s = 0 THEN
        SELECT status INTO v_current_status 
        FROM borrow_record WHERE record_id = p_record_id;
        
        IF v_current_status = '已还' THEN
            SET p_state = 2;
            SET p_message = '该书已经归还过了';
            SET s = 2;
        END IF;
    END IF;
    
    -- ========== 3. 获取借阅信息 ==========
    IF s = 0 THEN
        SELECT due_date, student_id, book_id 
        INTO v_due_date, v_student_id, v_book_id
        FROM borrow_record WHERE record_id = p_record_id;
    END IF;
    
    -- ========== 4. 更新借阅记录 ==========
    IF s = 0 THEN
        UPDATE borrow_record 
        SET return_date = p_return_date, 
            status = IF(p_return_date > v_due_date, '逾期', '已还')
        WHERE record_id = p_record_id;
    END IF;
    
    -- ========== 5. 更新图书可借数量 ==========
    IF s = 0 THEN
        UPDATE book SET available_count = available_count + 1
        WHERE book_id = v_book_id;
    END IF;
    
    -- ========== 6. 计算逾期罚款 ==========
    IF s = 0 AND p_return_date > v_due_date THEN
        SET v_overdue_days = DATEDIFF(p_return_date, v_due_date);
        SET v_fine = v_overdue_days * 0.5;
        
        INSERT INTO overdue_record(borrow_id, student_id, overdue_days, fine_amount, paid_status)
        VALUES(p_record_id, v_student_id, v_overdue_days, v_fine, FALSE);
        
        SET p_message = CONCAT('还书成功，逾期', v_overdue_days, '天，罚款', v_fine, '元');
    ELSEIF s = 0 THEN
        SET p_message = '还书成功，无逾期';
    END IF;
    
    -- ========== 7. 根据执行结果提交或回滚 ==========
    IF s = 0 THEN
        COMMIT;
        SET p_state = 0;
    ELSE
        ROLLBACK;
        IF p_state = 0 THEN
            SET p_state = 3;
            SET p_message = '系统错误，还书失败';
        END IF;
    END IF;
END//
DELIMITER ;


-- =====================================================
-- 9. 函数：查询学生总罚款（保持不变）
-- =====================================================
DROP FUNCTION IF EXISTS `GetStudentTotalFine`;
DELIMITER //
CREATE FUNCTION `GetStudentTotalFine`(p_student_id VARCHAR(20))
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE total DECIMAL(10,2);
    SELECT IFNULL(SUM(fine_amount), 0) INTO total
    FROM overdue_record 
    WHERE student_id = p_student_id AND paid_status = FALSE;
    RETURN total;
END//
DELIMITER ;
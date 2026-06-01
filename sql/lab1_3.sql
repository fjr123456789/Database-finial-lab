USE `db_lab1`;
DROP procedure IF EXISTS updateReaderID;

DELIMITER $$
USE `db_lab1`$$
CREATE PROCEDURE updateReaderID (
    IN old_id CHAR(8),
    IN new_id CHAR(8),
    OUT state INT
    )
BEGIN
	DECLARE s INT DEFAULT 0;
    DECLARE old_exists INT;
    DECLARE new_exists INT;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET s = 1;
    
    START TRANSACTION;
    
     -- 检查旧读者ID是否存在
    SELECT COUNT(*) FROM Reader WHERE rid = old_id INTO old_exists;
    
    -- 检查新读者ID是否已被占用
	SELECT COUNT(*) FROM Reader WHERE rid = new_id INTO new_exists;
    
     -- 验证条件
    IF old_exists = 0 THEN
        SET s = 2;
    ELSEIF new_exists > 0 THEN
        SET s = 3;
    END IF;
    
    -- 执行更新操作
    IF s = 0 THEN
		-- 先插入新ID（临时保留旧ID），否则更改R999在borrow会因为外键链接不在reader中而报错
		INSERT INTO Reader (rid, rname, age, address) 
		SELECT new_id, rname, age, address FROM Reader WHERE rid = old_id;

        UPDATE Borrow SET reader_ID = new_id WHERE reader_ID = old_id; -- 更新borrow
        UPDATE Reserve SET reader_ID = new_id WHERE reader_ID = old_id; -- 更新预约表
		DELETE FROM Reader WHERE rid = old_id;	-- 删除旧ID
    END IF;
    
    IF s = 0 THEN
		SET state = 0;
        COMMIT;    -- 成功
    ELSE
		SET state = s;
        ROLLBACK; -- 失败
    END IF;
END$$

DELIMITER ;

-- 测试：将R006改为R999
CALL updateReaderID('R006', 'R999', @state);
SELECT @state;


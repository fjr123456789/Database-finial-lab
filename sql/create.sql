
-- =====================================================
-- 建数据库
-- =====================================================
DROP DATABASE IF EXISTS `finial_lab`;
CREATE DATABASE `finial_lab` 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

USE `finial_lab`;

-- =====================================================
-- 学生表
-- =====================================================
DROP TABLE IF EXISTS `student`;
CREATE TABLE `student` (
    `student_id` VARCHAR(20) PRIMARY KEY COMMENT '学号',
    `name` VARCHAR(50) NOT NULL COMMENT '姓名',
    `password` VARCHAR(100) NOT NULL COMMENT '密码',
    `phone` VARCHAR(20) DEFAULT NULL COMMENT '手机号',
    `email` VARCHAR(100) DEFAULT NULL COMMENT '邮箱',
    `image` VARCHAR(255) DEFAULT 'doc/image/default.png' COMMENT '头像路径'-- ,
) ;

-- =====================================================
-- 管理员表
-- =====================================================
DROP TABLE IF EXISTS `admin`;
CREATE TABLE `admin` (
    `admin_id` VARCHAR(20) PRIMARY KEY COMMENT '管理员账号',
    `name` VARCHAR(50) NOT NULL COMMENT '姓名',
    `password` VARCHAR(100) NOT NULL COMMENT '密码'
);

-- =====================================================
-- 图书表
-- =====================================================
DROP TABLE IF EXISTS `book`;
CREATE TABLE `book` (
    `book_id` VARCHAR(20) PRIMARY KEY COMMENT '图书编号',
    `title` VARCHAR(200) NOT NULL COMMENT '书名',
    `author` VARCHAR(100) DEFAULT NULL COMMENT '作者',
    `publisher` VARCHAR(100) DEFAULT NULL COMMENT '出版社',
    `total_count` INT DEFAULT 1 COMMENT '总数量',
    `available_count` INT DEFAULT 1 COMMENT '可借数量',
    `content` VARCHAR(255) DEFAULT NULL COMMENT '内容路径',
    `cover_image` VARCHAR(255) DEFAULT 'doc/image/default.png' COMMENT '封面图片'-- ,
) ;

-- =====================================================
-- 借阅记录表
-- =====================================================
DROP TABLE IF EXISTS `borrow_record`;
CREATE TABLE `borrow_record` (
    `record_id` INT PRIMARY KEY AUTO_INCREMENT COMMENT '借阅ID',
    `student_id` VARCHAR(20) NOT NULL COMMENT '学号',
    `book_id` VARCHAR(20) NOT NULL COMMENT '图书编号',
    `borrow_date` DATE NOT NULL COMMENT '借书日期',
--     `due_date` DATE NOT NULL COMMENT '应还日期',
    `return_date` DATE DEFAULT NULL COMMENT '实际归还日期',
--     `status` ENUM('借阅中', '已还', '逾期') DEFAULT '借阅中' COMMENT '状态',
    FOREIGN KEY (`student_id`) REFERENCES `student`(`student_id`) ON DELETE CASCADE,
    FOREIGN KEY (`book_id`) REFERENCES `book`(`book_id`) ON DELETE CASCADE-- ,

);

-- =====================================================
-- 预定记录表
-- =====================================================
DROP TABLE IF EXISTS `reservation_record`;
CREATE TABLE `reservation_record` (
    `reserve_id` INT PRIMARY KEY AUTO_INCREMENT COMMENT '预定ID',
    `student_id` VARCHAR(20) NOT NULL COMMENT '学号',
    `book_id` VARCHAR(20) NOT NULL COMMENT '图书编号',
    `reserve_date` DATE NOT NULL COMMENT '预定日期',
    `status` ENUM('等待中', '已取书', '已取消') DEFAULT '等待中' COMMENT '状态',
    FOREIGN KEY (`student_id`) REFERENCES `student`(`student_id`)  ON DELETE CASCADE,
    FOREIGN KEY (`book_id`) REFERENCES `book`(`book_id`) ON DELETE CASCADE
);

-- =====================================================
-- 逾期记录表
-- =====================================================
DROP TABLE IF EXISTS `overdue_record`;
CREATE TABLE `overdue_record` (
    `overdue_id` INT PRIMARY KEY AUTO_INCREMENT COMMENT '逾期ID',
    `borrow_id` INT NOT NULL COMMENT '借阅记录ID',
--     `student_id` VARCHAR(20) NOT NULL COMMENT '学号',
--     `overdue_days` INT DEFAULT 0 COMMENT '逾期天数',
--     `fine_amount` DECIMAL(10,2) DEFAULT 0 COMMENT '罚款金额',
    `paid_status` BOOLEAN DEFAULT FALSE COMMENT '是否已缴费',
    `paid_date` DATE DEFAULT NULL COMMENT '缴费日期',
    FOREIGN KEY (`borrow_id`) REFERENCES `borrow_record`(`record_id`) ON DELETE CASCADE-- ,
);




DROP TRIGGER IF EXISTS `after_borrow_insert`;
DELIMITER //

CREATE TRIGGER `after_borrow_insert`
AFTER INSERT ON `borrow_record`
FOR EACH ROW
BEGIN
    -- 只有插入的 return_date 为空时，才减少可借数量
    IF NEW.return_date IS NULL THEN
        UPDATE `book` SET `available_count` = `available_count` - 1
        WHERE `book_id` = NEW.`book_id`;
    END IF;
END//

DELIMITER ;

-- =====================================================
-- 触发器：还书后自动更新数量
-- =====================================================

DROP TRIGGER IF EXISTS `after_borrow_update`;
DELIMITER //

CREATE TRIGGER `after_borrow_update`
AFTER UPDATE ON `borrow_record`
FOR EACH ROW
BEGIN
    -- 当 return_date 从 NULL 变为 非 NULL 时，才增加可借数量
    IF OLD.return_date IS NULL AND NEW.return_date IS NOT NULL THEN
        UPDATE `book` SET `available_count` = `available_count` + 1
        WHERE `book_id` = NEW.`book_id`;
    END IF;
END//

DELIMITER ;




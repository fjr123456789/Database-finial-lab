-- =====================================================
-- 图书馆信息管理系统 - 完整数据库脚本
-- 包含：建表、存储过程、函数、触发器、初始数据
-- 已统一字符集为 utf8mb4，排序规则为 utf8mb4_unicode_ci
-- =====================================================

-- =====================================================
-- 1. 创建数据库（如果不存在）
-- =====================================================
DROP DATABASE IF EXISTS `finial_lab`;
CREATE DATABASE `finial_lab` 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

USE `finial_lab`;

-- =====================================================
-- 2. 学生表
-- =====================================================
DROP TABLE IF EXISTS `student`;
CREATE TABLE `student` (
    `student_id` VARCHAR(20) PRIMARY KEY COMMENT '学号',
    `name` VARCHAR(50) NOT NULL COMMENT '姓名',
    `password` VARCHAR(100) NOT NULL COMMENT '密码',
    `phone` VARCHAR(20) DEFAULT NULL COMMENT '手机号',
    `email` VARCHAR(100) DEFAULT NULL COMMENT '邮箱',
    `avatar` VARCHAR(255) DEFAULT NULL COMMENT '头像路径'-- ,
   --  INDEX `idx_name` (`name`),
--     INDEX `idx_phone` (`phone`)
) ;-- ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='学生表';

-- =====================================================
-- 3. 管理员表
-- =====================================================
DROP TABLE IF EXISTS `admin`;
CREATE TABLE `admin` (
    `admin_id` VARCHAR(20) PRIMARY KEY COMMENT '管理员账号',
    `name` VARCHAR(50) NOT NULL COMMENT '姓名',
    `password` VARCHAR(100) NOT NULL COMMENT '密码'
);--  ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='管理员表';

-- =====================================================
-- 4. 图书表
-- =====================================================
DROP TABLE IF EXISTS `book`;
CREATE TABLE `book` (
    `book_id` VARCHAR(20) PRIMARY KEY COMMENT '图书编号',
    `title` VARCHAR(200) NOT NULL COMMENT '书名',
    `author` VARCHAR(100) DEFAULT NULL COMMENT '作者',
    `publisher` VARCHAR(100) DEFAULT NULL COMMENT '出版社',
    -- `category` VARCHAR(50) DEFAULT NULL COMMENT '分类',
    `total_count` INT DEFAULT 1 COMMENT '总数量',
    `available_count` INT DEFAULT 1 COMMENT '可借数量',
    `cover_image` VARCHAR(255) DEFAULT NULL COMMENT '封面图片'-- ,
    -- `description` TEXT DEFAULT NULL COMMENT '图书简介',
    -- `location` VARCHAR(50) DEFAULT NULL COMMENT '存放位置',
   --  `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '入库时间',
--     INDEX `idx_title` (`title`),
--     INDEX `idx_author` (`author`),
--     INDEX `idx_category` (`category`)
) ;-- ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='图书表';

-- =====================================================
-- 5. 借阅记录表
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
    -- `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (`student_id`) REFERENCES `student`(`student_id`) ON DELETE CASCADE,
    FOREIGN KEY (`book_id`) REFERENCES `book`(`book_id`) ON DELETE CASCADE-- ,
--     INDEX `idx_student` (`student_id`),
--     INDEX `idx_book` (`book_id`),
--     INDEX `idx_status` (`status`),
--     INDEX `idx_due_date` (`due_date`)
) ;-- ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='借阅记录表';

-- =====================================================
-- 6. 预定记录表
-- =====================================================
DROP TABLE IF EXISTS `reservation_record`;
CREATE TABLE `reservation_record` (
    `reserve_id` INT PRIMARY KEY AUTO_INCREMENT COMMENT '预定ID',
    `student_id` VARCHAR(20) NOT NULL COMMENT '学号',
    `book_id` VARCHAR(20) NOT NULL COMMENT '图书编号',
    `reserve_date` DATE NOT NULL COMMENT '预定日期',
    `expire_date` DATE DEFAULT NULL COMMENT '过期日期',
    `status` ENUM('等待中', '已取书', '已取消') DEFAULT '等待中' COMMENT '状态',
    -- `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (`student_id`) REFERENCES `student`(`student_id`)  ON DELETE CASCADE,
    FOREIGN KEY (`book_id`) REFERENCES `book`(`book_id`) ON DELETE CASCADE
--     INDEX `idx_student` (`student_id`),
--     INDEX `idx_book` (`book_id`)
);--  ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='预定记录表';

-- =====================================================
-- 7. 逾期记录表
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
    -- `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (`borrow_id`) REFERENCES `borrow_record`(`record_id`) ON DELETE CASCADE-- ,
--     FOREIGN KEY (`student_id`) REFERENCES `student`(`student_id`) ON DELETE CASCADE
--     INDEX `idx_student` (`student_id`),
--     INDEX `idx_paid` (`paid_status`)
);--  ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='逾期记录表';


-- =====================================================
-- 10. 触发器：借书后自动减少可借数量
-- =====================================================
DROP TRIGGER IF EXISTS `after_borrow_insert`;
DELIMITER //
CREATE TRIGGER `after_borrow_insert`
AFTER INSERT ON `borrow_record`
FOR EACH ROW
BEGIN
    UPDATE `book` SET `available_count` = `available_count` - 1
    WHERE `book_id` = NEW.`book_id`;
END//
DELIMITER ;



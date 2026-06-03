-- =====================================================
-- 12. 插入初始数据
-- =====================================================
USE `finial_lab`;

-- 关闭外键检查
SET FOREIGN_KEY_CHECKS = 0;

-- 清空所有表
TRUNCATE TABLE borrow_record;
TRUNCATE TABLE reservation_record;
TRUNCATE TABLE overdue_record;
TRUNCATE TABLE book;
TRUNCATE TABLE student;
TRUNCATE TABLE admin;

-- 恢复外键检查
SET FOREIGN_KEY_CHECKS = 1;
-- 插入管理员
INSERT INTO `admin` (`admin_id`, `name`, `password`) VALUES
('admin001', '系统管理员', '123456');

-- 插入学生
INSERT INTO `student` (`student_id`, `name`, `password`, `phone`, `email`) VALUES
('001', '张三', '123456', '157001', 'zhangsan@example.com'),
('002', '李四', '123456', '157001', 'lisi@example.com'),
('003', '王五', '123456', '157001', 'wangwu@example.com'),
('004', '赵六', '123456', '157001', 'zhaoliu@example.com'),
('005', '赵六', '123456', '157001', 'zhaoliu@example.com'),
('006', '赵六', '123456', '157001', 'zhaoliu@example.com'),
('007', '赵六', '123456', '157001', 'zhaoliu@example.com'),
('008', '赵六', '123456', '157001', 'zhaoliu@example.com'),
('009', '赵六', '123456', '157001', 'zhaoliu@example.com'),
('100', '赵六', '123456', '157001', 'zhaoliu@example.com'),
('011', '赵六', '123456', '157001', 'zhaoliu@example.com');

-- 插入图书
INSERT INTO `book` (`book_id`, `title`, `author`, `publisher`, `total_count`, `available_count`,`cover_image`,`content`) VALUES
('B001', '分成两半的子爵', '卡尔维诺', 'Yilin Press', 3, 3, 'uploads/covers/img.png', 'uploads/content/B001.pdf'),
('B002', '沙之书', '豪尔赫·路易斯·博尔赫斯', '上海译文出版社', 2, 2,'doc/image/default.png',''),
('B003', '十日谈', '薄伽丘', '人民文学出版社', 2, 2, 'doc/image/default.png',''),
('B004', '银河系漫游指南', '道格拉斯·亚当斯', '四川科学技术出版社', 2, 2, 'doc/image/default.png',''),
('B005', '宇宙尽头的餐馆', '道格拉斯·亚当斯', '四川科学技术出版社', 1, 1, 'doc/image/default.png',''),
('B006', '生命宇宙以及一切', '道格拉斯·亚当斯', '四川科学技术出版社', 2, 2, 'doc/image/default.png',''),
('B007', '再见,谢谢鱼', '道格拉斯·亚当斯', '四川科学技术出版社', 2, 2, 'doc/image/default.png',''),
('B008', '基本上无害', '道格拉斯·亚当斯', '四川科学技术出版社', 2, 2, 'doc/image/default.png',''),
('B009', '宇宙尽头的餐馆', '道格拉斯·亚当斯', '四川科学技术出版社', 2, 2, 'doc/image/default.png',''),
('B010', '宇宙尽头的餐馆', '道格拉斯·亚当斯', '四川科学技术出版社', 2, 2, 'doc/image/default.png',''),
('B011', '宇宙尽头的餐馆', '道格拉斯·亚当斯', '四川科学技术出版社', 2, 2, 'doc/image/default.png','');

-- 插入借阅记录示例
-- 当前借阅（未逾期）
INSERT INTO `borrow_record` (`student_id`, `book_id`, `borrow_date`, `return_date`) VALUES
('001', 'B001', DATE_SUB(CURDATE(), INTERVAL 10 DAY), DATE_ADD(CURDATE(), INTERVAL 20 DAY)),
('002', 'B003', DATE_SUB(CURDATE(), INTERVAL 5 DAY), DATE_ADD(CURDATE(), INTERVAL 25 DAY)),
('003', 'B004', DATE_SUB(CURDATE(), INTERVAL 3 DAY), DATE_ADD(CURDATE(), INTERVAL 27 DAY));

-- 逾期借阅（已逾期）
INSERT INTO `borrow_record` (`student_id`, `book_id`, `borrow_date`) VALUES
('001', 'B002', DATE_SUB(CURDATE(), INTERVAL 35 DAY)),
('002', 'B005', DATE_SUB(CURDATE(), INTERVAL 40 DAY));

-- 已归还记录（历史）
INSERT INTO `borrow_record` (`student_id`, `book_id`, `borrow_date`, `return_date`) VALUES
('003', 'B001', DATE_SUB(CURDATE(), INTERVAL 60 DAY), DATE_SUB(CURDATE(), INTERVAL 28 DAY)),
('001', 'B003', DATE_SUB(CURDATE(), INTERVAL 50 DAY), DATE_SUB(CURDATE(), INTERVAL 25 DAY)),
('004', 'B006', DATE_SUB(CURDATE(), INTERVAL 30 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY));

-- 插入逾期罚款记录（对应上面的逾期借阅）
INSERT INTO `overdue_record` (`borrow_id`, `paid_status`) VALUES
(4, FALSE),   -- 对应 record_id=4 的逾期
(5, FALSE);   -- 对应 record_id=5 的逾期

-- 插入预定记录示例
INSERT INTO `reservation_record` (`student_id`, `book_id`, `reserve_date`, `status`) VALUES
('004', 'B007', CURDATE(), '等待中'),
('002', 'B002', CURDATE(), '等待中'),
('001', 'B010', CURDATE(), '等待中');


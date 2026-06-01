-- =====================================================
-- 12. 插入初始数据
-- =====================================================
USE `finial_lab`;
-- 插入管理员
INSERT INTO `admin` (`admin_id`, `name`, `password`) VALUES
('admin001', '系统管理员', '123456'),
('admin002', '张老师', '123456');

-- 插入学生
INSERT INTO `student` (`student_id`, `name`, `password`, `phone`, `email`) VALUES
('2021001', '张三', '123456', '13800138001', 'zhangsan@example.com'),
('2021002', '李四', '123456', '13800138002', 'lisi@example.com'),
('2021003', '王五', '123456', '13800138003', 'wangwu@example.com'),
('2021004', '赵六', '123456', '13800138004', 'zhaoliu@example.com');

-- 插入图书
INSERT INTO `book` (`book_id`, `title`, `author`, `publisher`, `total_count`, `available_count`) VALUES
('B001', 'Python编程从入门到实践', 'Eric Matthes', '人民邮电出版社', 3, 3),
('B002', '数据库系统概念', 'Abraham Silberschatz', '机械工业出版社', 2, 2),
('B003', 'Flask Web开发', 'Miguel Grinberg', '人民邮电出版社', 2, 2),
('B004', '深入理解计算机系统', 'Randal E. Bryant', '机械工业出版社', 2, 2),
('B005', '算法导论', 'Thomas H. Cormen', '机械工业出版社', 1, 1),
('B006', 'Java编程思想', 'Bruce Eckel', '机械工业出版社', 2, 2),
('B007', '设计模式', 'Erich Gamma', '清华大学出版社', 2, 2);

-- 插入借阅记录示例（包含正常借阅和逾期借阅）
-- 当前借阅（未逾期）
INSERT INTO `borrow_record` (`student_id`, `book_id`, `borrow_date`, `due_date`, `status`) VALUES
('2021001', 'B001', DATE_SUB(CURDATE(), INTERVAL 10 DAY), DATE_ADD(CURDATE(), INTERVAL 20 DAY), '借阅中'),
('2021002', 'B003', DATE_SUB(CURDATE(), INTERVAL 5 DAY), DATE_ADD(CURDATE(), INTERVAL 25 DAY), '借阅中'),
('2021003', 'B004', DATE_SUB(CURDATE(), INTERVAL 3 DAY), DATE_ADD(CURDATE(), INTERVAL 27 DAY), '借阅中');

-- 逾期借阅（已逾期）
INSERT INTO `borrow_record` (`student_id`, `book_id`, `borrow_date`, `due_date`, `status`) VALUES
('2021001', 'B002', DATE_SUB(CURDATE(), INTERVAL 35 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY), '借阅中'),
('2021002', 'B005', DATE_SUB(CURDATE(), INTERVAL 40 DAY), DATE_SUB(CURDATE(), INTERVAL 10 DAY), '借阅中');

-- 已归还记录（历史）
INSERT INTO `borrow_record` (`student_id`, `book_id`, `borrow_date`, `due_date`, `return_date`, `status`) VALUES
('2021003', 'B001', DATE_SUB(CURDATE(), INTERVAL 60 DAY), DATE_SUB(CURDATE(), INTERVAL 30 DAY), DATE_SUB(CURDATE(), INTERVAL 28 DAY), '已还'),
('2021001', 'B003', DATE_SUB(CURDATE(), INTERVAL 50 DAY), DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 25 DAY), '逾期'),
('2021004', 'B006', DATE_SUB(CURDATE(), INTERVAL 30 DAY), DATE_SUB(CURDATE(), INTERVAL 0 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY), '已还');

-- 插入逾期罚款记录（对应上面的逾期借阅）
INSERT INTO `overdue_record` (`borrow_id`, `student_id`, `overdue_days`, `fine_amount`, `paid_status`) VALUES
(4, '2021001', 30, 15.00, FALSE),   -- 对应 record_id=4 的逾期
(5, '2021002', 40, 20.00, FALSE);   -- 对应 record_id=5 的逾期

-- 插入预定记录示例
INSERT INTO `reservation_record` (`student_id`, `book_id`, `reserve_date`, `expire_date`, `status`) VALUES
('2021004', 'B007', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 7 DAY), '等待中'),
('2021002', 'B002', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 7 DAY), '等待中');


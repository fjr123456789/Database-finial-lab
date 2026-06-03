# models.py
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime, timedelta

db = SQLAlchemy()


class Student(db.Model):
    __tablename__ = 'student'
    __table_args__ = {'extend_existing': True}

    student_id = db.Column(db.String(20), primary_key=True)
    name = db.Column(db.String(50), nullable=False)
    password = db.Column(db.String(100), nullable=False)
    phone = db.Column(db.String(20))
    email = db.Column(db.String(100))
    image = db.Column(db.String(255), default='static/doc/image/default.png')
    # created_at = db.Column(db.DateTime, default=datetime.now)

    # 关系
    borrow_records = db.relationship('BorrowRecord', backref='student', lazy='dynamic')
    reservations = db.relationship('ReservationRecord', backref='student', lazy='dynamic')

    def get_id(self):
        return self.student_id

    def __repr__(self):
        return f'<Student {self.student_id}>'


class Admin(db.Model):
    __tablename__ = 'admin'
    __table_args__ = {'extend_existing': True}

    admin_id = db.Column(db.String(20), primary_key=True)
    name = db.Column(db.String(50), nullable=False)
    password = db.Column(db.String(100), nullable=False)
    # created_at = db.Column(db.DateTime, default=datetime.now)

    def get_id(self):
        return self.admin_id

    def __repr__(self):
        return f'<Admin {self.admin_id}>'


class Book(db.Model):
    __tablename__ = 'book'
    __table_args__ = {'extend_existing': True}

    book_id = db.Column(db.String(20), primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    author = db.Column(db.String(100))
    publisher = db.Column(db.String(100))
    total_count = db.Column(db.Integer, default=1)
    available_count = db.Column(db.Integer, default=1)
    cover_image = db.Column(db.String(255), default='static/doc/image/default.png')
    content = db.Column(db.String(255))

    def is_available(self):
        return self.available_count > 0

    def __repr__(self):
        return f'<Book {self.title}>'


class BorrowRecord(db.Model):
    __tablename__ = 'borrow_record'
    __table_args__ = {'extend_existing': True}

    record_id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    student_id = db.Column(db.String(20), db.ForeignKey('student.student_id'))
    book_id = db.Column(db.String(20), db.ForeignKey('book.book_id'))
    borrow_date = db.Column(db.Date, nullable=False)
    return_date = db.Column(db.Date)
    @property
    def due_date(self):
        """动态计算应还日期（假设借期30天）"""
        return self.borrow_date + timedelta(days=30)

    @property
    def status(self):
        """动态计算状态"""
        if self.return_date:
            return '已还'
        elif self.due_date < datetime.now().date():
            return '逾期'
        else:
            return '借阅中'

    book = db.relationship('Book', backref='borrow_records')

    def __repr__(self):
        return f'<BorrowRecord {self.record_id}>'


class ReservationRecord(db.Model):
    __tablename__ = 'reservation_record'
    __table_args__ = {'extend_existing': True}

    reserve_id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    student_id = db.Column(db.String(20), db.ForeignKey('student.student_id'))
    book_id = db.Column(db.String(20), db.ForeignKey('book.book_id'))
    reserve_date = db.Column(db.Date, nullable=False)
    status = db.Column(db.String(20), default='等待中')

    book = db.relationship('Book', backref='reservations')

    def __repr__(self):
        return f'<ReservationRecord {self.reserve_id}>'


class OverdueRecord(db.Model):
    __tablename__ = 'overdue_record'
    __table_args__ = {'extend_existing': True}

    overdue_id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    borrow_id = db.Column(db.Integer, db.ForeignKey('borrow_record.record_id'))
    # student_id = db.Column(db.String(20), db.ForeignKey('student.student_id'))
    # overdue_days = db.Column(db.Integer, default=0)
    # fine_amount = db.Column(db.Numeric(10, 2), default=0)
    paid_status = db.Column(db.Boolean, default=False)
    paid_date = db.Column(db.Date)
    # created_at = db.Column(db.DateTime, default=datetime.now)

    borrow = db.relationship('BorrowRecord', backref='overdue')


    def __repr__(self):
        return f'<OverdueRecord {self.overdue_id}>'

class OverdueRecordView(db.Model):
    """逾期记录视图（只读）"""
    __tablename__ = 'overdue_record_view'
    __table_args__ = {'extend_existing': True, 'info': {'is_view': True}}
    overdue_id = db.Column(db.Integer, primary_key=True)
    borrow_id = db.Column(db.Integer)
    student_id = db.Column(db.String(20))
    student_name = db.Column(db.String(50))
    book_id = db.Column(db.String(20))
    book_title = db.Column(db.String(200))
    borrow_date = db.Column(db.Date)
    return_date = db.Column(db.Date)
    due_date = db.Column(db.Date)
    overdue_days = db.Column(db.Integer)
    fine_amount = db.Column(db.Numeric(10, 2))
    paid_status = db.Column(db.Boolean)
    paid_date = db.Column(db.Date)

    def __repr__(self):
        return f'<OverdueRecordView {self.overdue_id}>'
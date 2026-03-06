USE master;
GO


IF EXISTS (SELECT name FROM sys.databases WHERE name = N'RumeliCareDB')
BEGIN
    ALTER DATABASE RumeliCareDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE RumeliCareDB;
END
GO

CREATE DATABASE RumeliCareDB;
GO

USE RumeliCareDB;
GO


--  TABLOLARIN OLUÞTURULMASI


CREATE TABLE Bolumler (
    BolumID INT IDENTITY(1,1) PRIMARY KEY,
    Ad NVARCHAR(50) NOT NULL,
    Kat INT,
    CalismaSaatleri NVARCHAR(50)
);

CREATE TABLE Doktorlar (
    DoktorID INT IDENTITY(1,1) PRIMARY KEY,
    SicilNo NVARCHAR(20) UNIQUE NOT NULL,
    AdSoyad NVARCHAR(100) NOT NULL,
    UzmanlikAlani NVARCHAR(50),
    Tel NVARCHAR(15),
    MuayeneUcreti DECIMAL(10,2) NOT NULL,
    BolumID INT NOT NULL,
    CONSTRAINT FK_Doktor_Bolum FOREIGN KEY (BolumID) REFERENCES Bolumler(BolumID)
);

CREATE TABLE Hastalar (
    HastaID INT IDENTITY(1,1) PRIMARY KEY,
    TCNo CHAR(11) UNIQUE NOT NULL,
    AdSoyad NVARCHAR(100) NOT NULL,
    DogumTarihi DATE,
    Cinsiyet CHAR(1),
    Tel NVARCHAR(15),
    Adres NVARCHAR(255),
    KanGrubu NVARCHAR(5),
    Alerjiler NVARCHAR(MAX), 
    KayitTarihi DATETIME DEFAULT GETDATE(),
    SonZiyaretTarihi DATETIME
);

CREATE TABLE Ilaclar (
    IlacID INT IDENTITY(1,1) PRIMARY KEY,
    Ad NVARCHAR(100) NOT NULL,
    EtkenMadde NVARCHAR(100),
    Fiyat DECIMAL(10,2)
);

CREATE TABLE Randevular (
    RandevuID INT IDENTITY(1,1) PRIMARY KEY,
    HastaID INT NOT NULL,
    DoktorID INT NOT NULL,
    Tarih DATE NOT NULL,
    Saat TIME NOT NULL,
    Durum NVARCHAR(20) DEFAULT 'Bekliyor',
    OlusturmaTarihi DATETIME DEFAULT GETDATE(),
    IptalTarihi DATETIME,
    CONSTRAINT FK_Randevu_Hasta FOREIGN KEY (HastaID) REFERENCES Hastalar(HastaID),
    CONSTRAINT FK_Randevu_Doktor FOREIGN KEY (DoktorID) REFERENCES Doktorlar(DoktorID)
);

CREATE TABLE Muayeneler (
    MuayeneID INT IDENTITY(1,1) PRIMARY KEY,
    RandevuID INT UNIQUE NOT NULL,
    Sikayet NVARCHAR(MAX),
    Teshis NVARCHAR(MAX),
    TedaviNotu NVARCHAR(MAX),
    KontrolGerekliMi BIT DEFAULT 0,
    CONSTRAINT FK_Muayene_Randevu FOREIGN KEY (RandevuID) REFERENCES Randevular(RandevuID)
);

CREATE TABLE Faturalar (
    FaturaID INT IDENTITY(1,1) PRIMARY KEY,
    MuayeneID INT NOT NULL,
    Tutar DECIMAL(10,2),
    Durum NVARCHAR(20) DEFAULT 'Bekliyor',
    OdemeYontemi NVARCHAR(20), 
    OdemeTarihi DATETIME,
    OlusturmaTarihi DATETIME DEFAULT GETDATE(),
    CONSTRAINT FK_Fatura_Muayene FOREIGN KEY (MuayeneID) REFERENCES Muayeneler(MuayeneID)
);

CREATE TABLE Receteler (
    ReceteID INT IDENTITY(1,1) PRIMARY KEY,
    MuayeneID INT NOT NULL,
    Tarih DATETIME DEFAULT GETDATE(),
    CONSTRAINT FK_Recete_Muayene FOREIGN KEY (MuayeneID) REFERENCES Muayeneler(MuayeneID)
);

CREATE TABLE ReceteDetay (
    ReceteDetayID INT IDENTITY(1,1) PRIMARY KEY,
    ReceteID INT NOT NULL,
    IlacID INT NOT NULL,
    Dozaj NVARCHAR(50),
    Talimat NVARCHAR(255),
    CONSTRAINT FK_ReceteDetay_Recete FOREIGN KEY (ReceteID) REFERENCES Receteler(ReceteID),
    CONSTRAINT FK_ReceteDetay_Ilac FOREIGN KEY (IlacID) REFERENCES Ilaclar(IlacID)
);

CREATE TABLE IslemLoglari (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    Islem NVARCHAR(50),
    Detay NVARCHAR(MAX),
    Tarih DATETIME DEFAULT GETDATE(),
    Kullanici NVARCHAR(50) DEFAULT SYSTEM_USER
);

-- Ýndeksler
CREATE INDEX IX_Randevu_Tarih ON Randevular(Tarih);
CREATE INDEX IX_Hasta_TC ON Hastalar(TCNo);
GO


--  TRIGGER, SP VE VIEW TANIMLARI


-- Trigger: Çakýþma Kontrolü
CREATE TRIGGER trg_RandevuCakismaKontrol ON Randevular AFTER INSERT AS
BEGIN
    DECLARE @DoktorID INT, @Tarih DATE, @Saat TIME, @Cnt INT;
    SELECT @DoktorID = DoktorID, @Tarih = Tarih, @Saat = Saat FROM inserted;
    SELECT @Cnt = COUNT(*) FROM Randevular WHERE DoktorID = @DoktorID AND Tarih = @Tarih AND Saat = @Saat AND Durum <> 'Ýptal';
    
    IF @Cnt > 1 BEGIN RAISERROR ('Çakýþma Var! Doktor bu saatte dolu.', 16, 1); ROLLBACK; RETURN; END
END;
GO

-- Trigger: Otomatik Fatura
CREATE TRIGGER trg_OtomatikFatura ON Muayeneler AFTER INSERT AS
BEGIN
    INSERT INTO Faturalar (MuayeneID, Tutar, Durum)
    SELECT i.MuayeneID, d.MuayeneUcreti, 'Bekliyor'
    FROM inserted i
    JOIN Randevular r ON i.RandevuID = r.RandevuID
    JOIN Doktorlar d ON r.DoktorID = d.DoktorID;
END;
GO

-- Trigger: Randevu Ýptal Log
CREATE TRIGGER trg_RandevuIptalLog ON Randevular AFTER UPDATE AS
BEGIN
    IF UPDATE(Durum) BEGIN
        INSERT INTO IslemLoglari (Islem, Detay)
        SELECT 'Ýptal', 'Randevu ID: ' + CAST(i.RandevuID AS NVARCHAR)
        FROM inserted i JOIN deleted d ON i.RandevuID = d.RandevuID
        WHERE i.Durum = 'Ýptal' AND d.Durum <> 'Ýptal';
        
        UPDATE Randevular SET IptalTarihi = GETDATE() 
        FROM Randevular r JOIN inserted i ON r.RandevuID = i.RandevuID
        WHERE i.Durum = 'Ýptal';
    END
END;
GO

-- Trigger: Hasta Son Ziyaret
CREATE TRIGGER trg_HastaSonZiyaret ON Muayeneler AFTER INSERT AS
BEGIN
    UPDATE Hastalar 
    SET SonZiyaretTarihi = GETDATE()
    FROM Hastalar h
    JOIN Randevular r ON h.HastaID = r.HastaID
    JOIN inserted i ON r.RandevuID = i.RandevuID;
END;
GO

-- Stored Procedures
CREATE PROCEDURE sp_RandevuOlustur @HastaID INT, @DoktorID INT, @Tarih DATE, @Saat TIME AS
BEGIN
    INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat) VALUES (@HastaID, @DoktorID, @Tarih, @Saat);
END;
GO

CREATE PROCEDURE sp_MuayeneTamamla @RandevuID INT, @Sikayet NVARCHAR(MAX), @Teshis NVARCHAR(MAX), @TedaviNotu NVARCHAR(MAX) AS
BEGIN
    UPDATE Randevular SET Durum = 'Tamamlandý' WHERE RandevuID = @RandevuID;
    INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (@RandevuID, @Sikayet, @Teshis, @TedaviNotu);
END;
GO

CREATE PROCEDURE sp_ReceteOlustur @MuayeneID INT, @IlacID INT, @Dozaj NVARCHAR(50), @Talimat NVARCHAR(255) AS
BEGIN
    DECLARE @ReceteID INT;
    SELECT @ReceteID = ReceteID FROM Receteler WHERE MuayeneID = @MuayeneID;
    IF @ReceteID IS NULL BEGIN INSERT INTO Receteler (MuayeneID) VALUES (@MuayeneID); SET @ReceteID = SCOPE_IDENTITY(); END
    INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (@ReceteID, @IlacID, @Dozaj, @Talimat);
END;
GO

CREATE PROCEDURE sp_GunlukRapor @Tarih DATE AS BEGIN SELECT COUNT(*) FROM Randevular WHERE Tarih = @Tarih; END;
GO
CREATE PROCEDURE sp_HastaGecmisi @HastaID INT AS BEGIN SELECT * FROM Randevular WHERE HastaID = @HastaID; END;
GO

-- Views
CREATE VIEW vw_BugununRandevulari AS SELECT * FROM Randevular WHERE Tarih = CAST(GETDATE() AS DATE);
GO
CREATE VIEW vw_OdenmemisFaturalar AS SELECT * FROM Faturalar WHERE Durum = 'Bekliyor';
GO


--  VERÝ GÝRÝÞÝ (SEED DATA)


INSERT INTO Bolumler (Ad, Kat, CalismaSaatleri) VALUES 
('Dahiliye', 1, '09:00-17:00'), ('Kardiyoloji', 2, '09:00-17:00'), ('Ortopedi', 1, '09:00-17:00'), 
('Dermatoloji', 3, '09:00-16:00'), ('Göz', 3, '09:00-17:00'), ('KBB', 2, '09:00-17:00');

INSERT INTO Doktorlar (SicilNo, AdSoyad, UzmanlikAlani, MuayeneUcreti, BolumID) VALUES
('DR01', 'Dr. ÝLHAN KALP', 'Kardiyoloji', 1500, 2), ('DR02', 'Dr. Aynur Yýldýz', 'Dahiliye', 1000, 1),
('DR03', 'Dr. Ali Karagenç', 'Ortopedi', 1200, 3), ('DR04', 'Dr. Zeynep Kara', 'Göz', 1100, 5),
('DR05', 'Dr. doða þendoðan', 'KBB', 1000, 6), ('DR06', 'Dr. Ecrin Þahin', 'Dermatoloji', 1300, 4),
('DR07', 'Dr. Ceren Yýldýz', 'Dahiliye', 1000, 1), ('DR08', 'Dr. emre öztürk', 'Kardiyoloji', 1500, 2),
('DR09', 'Dr. merve Aksoy', 'Göz', 1100, 5), ('DR10', 'Dr. bilal þahin', 'Ortopedi', 1200, 3);

INSERT INTO Ilaclar (Ad, EtkenMadde, Fiyat) VALUES
('Parol', 'Parasetamol', 50), ('Majezik', 'Flurbiprofen', 80), ('Arveles', 'Deksketoprofen', 70),
('Augmentin', 'Amoksisilin', 150), ('Klamoks', 'Amoksisilin', 140), ('Cipro', 'Siprofloksasin', 120),
('Nexium', 'Esomeprazol', 100), ('Lansor', 'Lansoprazol', 90), ('Ecopirin', 'Asetilsalisilik', 30),
('Coraspin', 'Asetilsalisilik', 40), ('Beloc', 'Metoprolol', 60), ('Vasoxen', 'Nebivolol', 85),
('Glifor', 'Metformin', 55), ('Matofin', 'Metformin', 60), ('Lantus', 'Insülin', 300),
('Ventolin', 'Salbutamol', 75), ('Aerius', 'Desloratadin', 65), ('Crebros', 'Levosetirizin', 70),
('Tylolhot', 'Parasetamol', 100), ('Nurofen', 'Ibuprofen', 90), ('Dolorex', 'Diklofenak', 60),
('Muscoril', 'Tiyokolþikosid', 80), ('Dikloron', 'Diklofenak', 55), ('Voltaren', 'Diklofenak', 95),
('Bepanthen', 'Dekspantenol', 110), ('Madecassol', 'Centella', 120), ('Fito', 'Triticum', 85),
('Advil', 'Ibuprofen', 95), ('Aspirin', 'Asetilsalisilik', 25), ('Talcid', 'Hidrotalsit', 45);

INSERT INTO Hastalar (TCNo, AdSoyad, Cinsiyet, Alerjiler) VALUES
('10000000001', 'Ahmet Alper ', 'E', NULL), 
('10000000002', 'Kübra Demir', 'K', 'Amoksisilin'),
('10000000003', 'Eyüp ertürk', 'E', NULL), 
('10000000004', 'Beyza Çelik', 'K', 'Parasetamol'),
('10000000005', 'Ali ince', 'E', NULL), 
('10000000006', 'Batuhan Þen', 'K', NULL),
('10000000007', 'Hasan Canan', 'E', 'Penisilin'), 
('10000000008', 'Çaðdaþ Akman', 'E', NULL),
('10000000009', 'Kývýlcým nurdan', 'K', NULL), 
('10000000010', 'Merve Özlem', 'K', NULL),
('10000000011', 'Emine baþak', 'K', 'Aspirin'), 
('10000000012', 'Cemal Yýlmaz', 'E', NULL),
('10000000013', 'Hamza Tekin', 'E', NULL), 
('10000000014', 'Burak Yýl', 'E', NULL),
('10000000015', 'Ertuðrul Can', 'E', NULL), 
('10000000016', 'Tuðrul Kul', 'E', NULL),
('10000000017', 'Okan Bay', 'E', 'Toz'), 
('10000000018', 'mine Sayan', 'K', NULL),
('10000000019', 'Gizem Karten', 'K', NULL), 
('10000000020', 'damla þölen', 'K', NULL);

-- Randevular
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (1, 2, '2026-01-12', '09:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (3, 5, '2026-01-12', '09:15', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (5, 3, '2026-01-12', '09:45', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (2, 1, '2026-01-12', '10:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (8, 6, '2026-01-12', '10:30', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (12, 4, '2026-01-12', '11:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (7, 2, '2026-01-12', '11:15', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (15, 8, '2026-01-12', '13:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (4, 9, '2026-01-12', '13:30', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (10, 10, '2026-01-12', '14:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (6, 5, '2026-01-12', '14:45', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (18, 1, '2026-01-13', '09:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (11, 7, '2026-01-13', '09:30', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (19, 3, '2026-01-13', '10:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (13, 2, '2026-01-13', '10:15', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (14, 6, '2026-01-13', '11:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (20, 4, '2026-01-13', '11:30', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (1, 8, '2026-01-13', '13:15', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (9, 10, '2026-01-13', '14:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (17, 1, '2026-01-13', '15:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (5, 9, '2026-01-14', '09:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (2, 2, '2026-01-14', '09:30', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (16, 5, '2026-01-14', '10:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (8, 3, '2026-01-14', '10:45', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (12, 6, '2026-01-14', '11:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (3, 7, '2026-01-14', '11:30', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (15, 8, '2026-01-14', '13:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (7, 4, '2026-01-14', '13:45', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (10, 2, '2026-01-14', '14:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (13, 10, '2026-01-14', '15:30', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (4, 1, '2026-01-15', '09:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (6, 5, '2026-01-15', '09:15', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (11, 3, '2026-01-15', '10:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (19, 9, '2026-01-15', '10:30', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (14, 6, '2026-01-15', '11:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (1, 7, '2026-01-15', '11:45', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (18, 2, '2026-01-15', '13:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (9, 4, '2026-01-15', '13:30', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (20, 8, '2026-01-15', '14:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (17, 10, '2026-01-15', '15:00', 'Tamamlandý');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (2, 3, '2026-01-16', '09:00', 'Bekliyor');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (5, 5, '2026-01-16', '09:30', 'Bekliyor');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (8, 1, '2026-01-16', '10:00', 'Bekliyor');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (12, 6, '2026-01-16', '10:30', 'Bekliyor');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (15, 2, '2026-01-16', '11:00', 'Bekliyor');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (7, 8, '2026-01-16', '11:30', 'Bekliyor');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (3, 9, '2026-01-16', '13:00', 'Bekliyor');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (16, 4, '2026-01-16', '13:30', 'Bekliyor');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (11, 7, '2026-01-16', '14:00', 'Bekliyor');
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat, Durum) VALUES (19, 10, '2026-01-16', '14:30', 'Bekliyor');

-- Muayeneler
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (1, 'Yüksek ateþ ve boðaz aðrýsý', 'Akut Tonsilit', 'Ýstirahate ek antibiyotik tedavisi baþlandý.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (2, 'Sað dizde þiddetli aðrý', 'Gonartroz (Kireçlenme)', 'Fizik tedavi önerildi, aðrý kesici reçete edildi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (3, 'Geçmeyen öksürük ve hýrýltý', 'Akut Bronþit', 'Bol sývý tüketimi ve buhar tedavisi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (4, 'Çarpýntý ve nefes darlýðý', 'Sinüs Taþikardisi', 'Kardiyoloji kontrolü ve EKG takibi yapýldý.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (5, 'Ciltte kýzarýklýk ve kaþýntý', 'Atopik Dermatit', 'Alerjenlerden uzak durulmalý, krem verildi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (6, 'Uzaðý görememe þikayeti', 'Miyopi', 'Gözlük numaralarý güncellendi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (7, 'Mide yanmasý ve ekþime', 'Gastroözofageal Reflü', 'Asitli yiyeceklerden diyet, mide koruyucu verildi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (8, 'Belden bacaða yayýlan aðrý', 'Lumber Disk Hernisi (Bel Fýtýðý)', 'Aðýr kaldýrmamalý, kas gevþetici verildi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (9, 'Bulanýk görme', 'Astigmatizma', 'Lens kullanýmý hakkýnda bilgilendirme yapýldý.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (10, 'Ayak bileðinde burkulma', 'Yumuþak Doku Travmasý', 'Soðuk uygulama ve bandaj önerildi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (11, 'Kulak çýnlamasý', 'Tinnitus', 'KBB takibi ve iþitme testi istendi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (12, 'Halsizlik ve yorgunluk', 'Demir Eksikliði Anemisi', 'Kan deðerleri düþük, takviye baþlandý.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (13, 'Sýk idrara çýkma', 'Ýdrar Yolu Enfeksiyonu', 'Bol su içilmesi ve antibiyotik kullanýmý.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (14, 'Yüzde sivilcelenme', 'Akne Vulgaris', 'Cilt temizliði eðitimi ve topikal tedavi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (15, 'Göðüs aðrýsý', 'Hipertansiyon', 'Tansiyon takibi ve tuzsuz diyet.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (16, 'Burun týkanýklýðý', 'Mevsimsel Allerjik Rinit', 'Antihistaminik tedavi düzenlendi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (17, 'Gözde sulanma ve batma', 'Konjonktivit', 'Göz damlasý ve hijyen uyarýsý.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (18, 'Baþ dönmesi', 'Vertigo', 'Ani hareketlerden kaçýnmalý, manevra yapýldý.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (19, 'Omuz aðrýsý', 'Rotator Manþet Sendromu', 'Omuz egzersizleri gösterildi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (20, 'Göz kapaðýnda þiþlik', 'Arpacýk (Hordeolum)', 'Sýcak pansuman önerildi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (21, 'Rutin kontrol', 'Saðlýklý', 'Herhangi bir patoloji saptanmadý.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (22, 'Hazýmsýzlýk', 'Dispepsi', 'Beslenme düzeni deðiþtirilmeli.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (23, 'Sýrtta sivilce', 'Folikülit', 'Antibakteriyel sabun kullanýmý önerildi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (24, 'Eklem þiþliði', 'Romatoid Artrit Þüphesi', 'Romatoloji bölümüne sevk edildi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (25, 'Boðazda gýcýk hissi', 'Kronik Farenjit', 'Sigara ve asitli içeceklerden uzak durulmalý.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (26, 'Boyun aðrýsý', 'Servikal Spazm', 'Sýcak uygulama ve kas gevþetici.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (27, 'Þiddetli baþ aðrýsý', 'Migren', 'Tetikleyici gýdalardan kaçýnma, atak tedavisi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (28, 'Gözde kuruluk', 'Göz Kuruluðu Sendromu', 'Suni gözyaþý damlasý reçete edildi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (29, 'Ayak mantarý', 'Tinea Pedis', 'Ayaklar kuru tutulmalý, antifungal krem.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (30, 'Topuk aðrýsý', 'Plantar Fasiit (Topuk Dikeni)', 'Tabanlýk kullanýmý ve egzersiz.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (31, 'Ateþ ve titreme', 'Viral Enfeksiyon', 'Semptomatik tedavi ve istirahat.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (32, 'Mide bulantýsý', 'Akut Gastrit', 'Haþlanmýþ patates diyeti önerildi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (33, 'Kuru öksürük', 'Üst Solunum Yolu Enf.', 'Pastil ve þurup verildi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (34, 'El bileði aðrýsý', 'Karpal Tünel Sendromu', 'Bileklik kullanýmý önerildi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (35, 'Cilt kuruluðu', 'Kserozis', 'Nemlendirici losyon önerildi.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (36, 'Gözde kýzarýklýk', 'Bakteriyel Konjonktivit', 'Antibiyotikli damla baþlandý.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (37, 'Ýþitme azlýðý', 'Buþon (Kulak Kiri)', 'Kulak lavajý (yýkama) yapýldý.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (38, 'Nefes almada zorluk', 'Septum Deviasyonu', 'Ameliyat seçeneði görüþüldü.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (39, 'Vitamin eksikliði', 'B12 Vitamini Eksikliði', 'Aylýk iðne tedavisi planlandý.');
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) VALUES (40, 'Kas aðrýlarý', 'Miyalji', 'Soðuk algýnlýðýna baðlý kas aðrýsý, istirahat.');

-- Reçeteler
INSERT INTO Receteler (MuayeneID) VALUES (1);
INSERT INTO Receteler (MuayeneID) VALUES (2);
INSERT INTO Receteler (MuayeneID) VALUES (3);
INSERT INTO Receteler (MuayeneID) VALUES (4);
INSERT INTO Receteler (MuayeneID) VALUES (5);
INSERT INTO Receteler (MuayeneID) VALUES (6);
INSERT INTO Receteler (MuayeneID) VALUES (7);
INSERT INTO Receteler (MuayeneID) VALUES (8);
INSERT INTO Receteler (MuayeneID) VALUES (9);
INSERT INTO Receteler (MuayeneID) VALUES (10);
INSERT INTO Receteler (MuayeneID) VALUES (11);
INSERT INTO Receteler (MuayeneID) VALUES (12);
INSERT INTO Receteler (MuayeneID) VALUES (13);
INSERT INTO Receteler (MuayeneID) VALUES (14);
INSERT INTO Receteler (MuayeneID) VALUES (15);
INSERT INTO Receteler (MuayeneID) VALUES (16);
INSERT INTO Receteler (MuayeneID) VALUES (17);
INSERT INTO Receteler (MuayeneID) VALUES (18);
INSERT INTO Receteler (MuayeneID) VALUES (19);
INSERT INTO Receteler (MuayeneID) VALUES (20);
INSERT INTO Receteler (MuayeneID) VALUES (21);
INSERT INTO Receteler (MuayeneID) VALUES (22);
INSERT INTO Receteler (MuayeneID) VALUES (23);
INSERT INTO Receteler (MuayeneID) VALUES (24);
INSERT INTO Receteler (MuayeneID) VALUES (25);
INSERT INTO Receteler (MuayeneID) VALUES (26);
INSERT INTO Receteler (MuayeneID) VALUES (27);
INSERT INTO Receteler (MuayeneID) VALUES (28);
INSERT INTO Receteler (MuayeneID) VALUES (29);
INSERT INTO Receteler (MuayeneID) VALUES (30);

--her hastaya iki ilaç reçete baþý
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (1, 4, '2x1', 'Sabah akþam tok karnýna (12 saat ara ile)');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (1, 1, '3x1', 'Ateþ düþmezse 6 saatte bir');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (2, 21, '2x1', 'Sabah akþam tok karnýna');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (2, 24, '2x1', 'Aðrýlý bölgeye masaj yaparak sürünüz');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (3, 19, '1x1', 'Gece yatmadan önce sýcak suya karýþtýrarak');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (3, 1, '1x1', 'Günde 3 defa tok karnýna');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (4, 11, '1x1', 'Sabahlarý aç karnýna (Tansiyon için)');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (4, 10, '1x1', 'Günde bir kez tok karnýna');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (5, 17, '1x1', 'Her akþam ayný saatte');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (5, 25, '2x1', 'Kýzarýk bölgelere ince tabaka halinde');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (6, 29, '1x1', 'Günde 3 defa, yemeklerden sonra');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (6, 7, '1x1', 'Sabah aç karnýna kahvaltýdan 30 dk önce');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (7, 7, '1x1', 'Sabah aç karnýna bir bardak su ile');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (7, 30, '2x1', 'Yemeklerden sonra çiðneyerek');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (8, 22, '2x1', 'Sabah akþam tok karnýna');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (8, 2, '2x1', 'Aðrý olduðunda tok karnýna');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (9, 1, '1x1', 'Baþ aðrýsý olursa');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (9, 29, '1x1', 'Günde bir kez tok');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (10, 23, '3x1', 'Þiþen bölgeye hafifçe sürünüz');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (10, 1, '1x1', 'Aðrý kesici olarak');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (11, 20, '1x1', 'Tok karnýna');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (11, 25, '1x1', 'Kulak çevresine');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (12, 29, '1x1', 'Tok karnýna');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (12, 1, '1x1', 'Ýhtiyaç halinde');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (13, 6, '2x1', 'Sabah akþam tok karnýna (12 saat ara)');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (13, 1, '2x1', 'Ateþ ve aðrý için');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (14, 26, '1x1', 'Sadece sivilceli bölgeye gece');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (14, 27, '2x1', 'Sabah akþam ince tabaka');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (15, 12, '1x1', 'Her gün ayný saatte, tercihen sabah');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (15, 10, '1x1', 'Öðle yemeðinden sonra');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (16, 17, '1x1', 'Gece yatmadan önce');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (16, 18, '1x1', 'Sabah tok karnýna');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (17, 25, '3x1', 'Göze temas ettirmeden çevresine');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (17, 1, '1x1', 'Aðrý olursa');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (18, 11, '1x1', 'Sabah tok');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (18, 1, '1x1', 'Baþ aðrýsý için');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (19, 22, '2x1', 'Sabah akþam tok');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (19, 24, '3x1', 'Aðrýlý bölgeye masaj');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (20, 29, '1x1', 'Tok karnýna');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (20, 1, '1x1', 'Aðrý durumunda');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (21, 1, '1x1', 'Gerekirse');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (21, 25, '1x1', 'Ellere bakým için');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (22, 8, '1x1', 'Sabah aç karnýna');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (22, 30, '1x1', 'Yemeklerden sonra');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (23, 27, '2x1', 'Temiz cilde sürünüz');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (23, 26, '1x1', 'Gece yatmadan');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (24, 3, '1x1', 'Tok karnýna günde 1');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (24, 24, '2x1', 'Eklem yerlerine sürünüz');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (25, 1, '1x1', 'Aðrý ve ateþ için');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (25, 19, '1x1', 'Gece yatmadan sýcak iç');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (26, 22, '2x1', 'Sabah akþam tok');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (26, 20, '1x1', 'Tok karnýna');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (27, 2, '1x1', 'Atak baþlangýcýnda tok');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (27, 1, '1x1', 'Destekleyici olarak');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (28, 25, '1x1', 'Göz çevresi kuruluðu için');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (28, 1, '1x1', 'Aðrý için');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (29, 26, '2x1', 'Kuru ve temiz ayaða');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (29, 27, '1x1', 'Gece');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (30, 21, '2x1', 'Tok karnýna');
INSERT INTO ReceteDetay (ReceteID, IlacID, Dozaj, Talimat) VALUES (30, 23, '3x1', 'Topuk bölgesine masaj');

-- Fatura Güncelleme
UPDATE Faturalar SET Durum = 'Ödendi', OdemeTarihi = GETDATE(), OdemeYontemi = 'Kredi Kartý' 
WHERE FaturaID % 2 = 0;

PRINT '---------------------------------------------------';
PRINT 'ÝÞLEM BAÞARIYLA TAMAMLANDI!';
PRINT '---------------------------------------------------';

-- =============================================
-- 5. KONTROL VE LÝSTELEME
-- (Tüm tablolarýn içeriði burada listelenir)
-- =============================================

PRINT 'TABLO 1: BOLUMLER';
SELECT * FROM Bolumler;

PRINT 'TABLO 2: DOKTORLAR';
SELECT * FROM Doktorlar;

PRINT 'TABLO 3: HASTALAR';
SELECT * FROM Hastalar;

PRINT 'TABLO 4: ILACLAR';
SELECT * FROM Ilaclar;

PRINT 'TABLO 5: RANDEVULAR';
SELECT * FROM Randevular;

PRINT 'TABLO 6: MUAYENELER';
SELECT * FROM Muayeneler;

PRINT 'TABLO 7: FATURALAR';
SELECT * FROM Faturalar;

PRINT 'TABLO 8: RECETELER';
SELECT * FROM Receteler;

PRINT 'TABLO 9: RECETE DETAYLARI';
SELECT * FROM ReceteDetay;

PRINT 'TABLO 10: ISLEM LOGLARI';
SELECT * FROM IslemLoglari;



--çakýþma kontrolü ayný anda bir doktor iki muayeneye giremez
-- Mevcut dolu randevuyu görelim
SELECT * FROM Randevular WHERE DoktorID = 5 AND Tarih = '2026-01-16' AND Saat = '09:30';

-- AYNI SAATE BAÞKA BÝR HASTAYA (Örn: HastaID 1) RANDEVU EKLEMEYE ÇALIÞALIM
-- Bu kodu çalýþtýrdýðýnda "Messages" kýsmýnda KIRMIZI HATA görmelisin.
BEGIN TRY
    INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat) 
    VALUES (1, 5, '2026-01-16', '09:30');
END TRY
BEGIN CATCH
    SELECT ERROR_MESSAGE() AS HataMesaji;
END CATCH;



--son ziyaret görüntüleme
-- Önce hastanýn mevcut bilgilerine bakalým (SonZiyaretTarihi'ne dikkat)
SELECT * FROM Hastalar 
WHERE HastaID = (SELECT HastaID FROM Randevular WHERE RandevuID = 40);

-- ÞÝMDÝ MUAYENEYÝ GÝRÝYORUZ (Bu iþlem trigger'ý çalýþtýrýr)
INSERT INTO Muayeneler (RandevuID, Sikayet, Teshis, TedaviNotu) 
VALUES (40, 'Test Baþ Aðrýsý', 'Migren', 'Ýlaç verildi');

-- SONUÇ KONTROLÜ
-- Hastanýn SonZiyaretTarihi güncellendi mi? (Bugünün tarihi olmalý)
SELECT * FROM Hastalar 
WHERE HastaID = (SELECT HastaID FROM Randevular WHERE RandevuID = 40);




--randevu iptal etme kontrolü
-- Önce iptal edeceðimiz randevuyu (Örn: ID 45) ve Log tablosunu kontrol edelim
SELECT * FROM Randevular WHERE RandevuID = 45;
SELECT * FROM IslemLoglari;

-- ÞÝMDÝ RANDEVUYU ÝPTAL EDÝYORUZ
UPDATE Randevular 
SET Durum = 'Ýptal' 
WHERE RandevuID = 45;

-- SONUÇLARI KONTROL ET
-- 1. Randevu durumu 'Ýptal' oldu mu?
SELECT * FROM Randevular WHERE RandevuID = 45;

-- 2. Log tablosuna kayýt düþtü mü?
SELECT * FROM IslemLoglari ORDER BY LogID DESC;



-- 1. Hasta Yoksa Ekleme durumu
IF NOT EXISTS (SELECT 1 FROM Hastalar WHERE TCNo = '12345678901')
    INSERT INTO Hastalar (TCNo, AdSoyad, Cinsiyet) VALUES ('12345678908', 'Ayyþe Yýlmaz', 'K');

-- 2. Randevuyu Oluþtur (ID'leri isme ve TC'ye göre otomatik bulur)
-- Not: Seed verilerinde 12 Ocak dolu olduðu için tarihi 17 Ocak yaptým.
INSERT INTO Randevular (HastaID, DoktorID, Tarih, Saat)
SELECT 
    (SELECT HastaID FROM Hastalar WHERE TCNo = '12345678901'),
    (SELECT DoktorID FROM Doktorlar WHERE AdSoyad = 'Dr. ÝLHAN KALP'),
    '2026-01-29', 
    '10:00';

-- Sonucu Göster
SELECT TOP 1 * FROM Randevular ORDER BY RandevuID DESC;





PRINT '=== AYLIK PERFORMANS RAPORU (OCAK 2026) ===';

-- 1. Randevu Durumlarý
SELECT 
    COUNT(*) as ToplamRandevu,
    SUM(CASE WHEN Durum = 'Tamamlandý' THEN 1 ELSE 0 END) as Tamamlanan,
    SUM(CASE WHEN Durum = 'Ýptal' THEN 1 ELSE 0 END) as IptalEdilen
FROM Randevular 
WHERE Tarih BETWEEN '2026-01-01' AND '2026-01-31';

-- 2. Bölüm Bazlý Gelir Daðýlýmý
SELECT 
    b.Ad as Bolum, 
    SUM(f.Tutar) as ToplamCiro
FROM Faturalar f
JOIN Muayeneler m ON f.MuayeneID = m.MuayeneID
JOIN Randevular r ON m.RandevuID = r.RandevuID
JOIN Doktorlar d ON r.DoktorID = d.DoktorID
JOIN Bolumler b ON d.BolumID = b.BolumID
WHERE f.OlusturmaTarihi BETWEEN '2026-01-01' AND '2026-01-31'
GROUP BY b.Ad
ORDER BY ToplamCiro DESC;

-- 3. En Çok Hasta Bakan Doktor
SELECT TOP 1 
    d.AdSoyad, 
    COUNT(r.RandevuID) as HastaSayisi
FROM Randevular r
JOIN Doktorlar d ON r.DoktorID = d.DoktorID
WHERE r.Durum = 'Tamamlandý' AND r.Tarih BETWEEN '2026-01-01' AND '2026-01-31'
GROUP BY d.AdSoyad
ORDER BY HastaSayisi DESC;
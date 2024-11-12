/*
1. Tạo link server in TargetDb to SourceDb
2. Backup schema from TargetDb to SourceDb
3. Run script
*/

/* CREATE LINK SERVER

exec sp_addlinkedserver
	@server = '...', -- server name/ IP
	@srvproduct ='',
	@provider = 'SQLNCLI',
	@datasrc = '...,' IP, port (if not has default)

exec sp_addlinkedsrvlogin	-- authenticate
	@rmtsrvname = '...',	-- is @server
	@useself = 'False',
	@locallogin = null,
	@rmtuser ='',
	@rmtpassword = ''

*/





DECLARE @TableName NVARCHAR(256)
DECLARE @SchemaName NVARCHAR(256)
DECLARE @sql NVARCHAR(MAX)
DECLARE @ColumnList NVARCHAR(MAX)
DECLARE @IdentityColumn NVARCHAR(128)
DECLARE @SourceSvr nvarchar(100) ='107.107.53.90'
DECLARE @SourceDb nvarchar(100) ='NEO_S_CMS'
DECLARE @StrSourceSvrAndDb nvarchar(200) ='[' + @SourceSvr + '].[' + @SourceDb + ']'
DECLARE @TargetDb nvarchar(100) ='NEO_S_CMS'
DECLARE @nrow nvarchar(50) = '1000'

DECLARE table_cursor CURSOR FOR 
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'

OPEN table_cursor

FETCH NEXT FROM table_cursor 
INTO @SchemaName, @TableName

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Tìm cột Identity
    SELECT @IdentityColumn = COLUMN_NAME
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = @SchemaName 
      AND TABLE_NAME = @TableName
      AND COLUMNPROPERTY(OBJECT_ID(TABLE_SCHEMA + '.' + TABLE_NAME), COLUMN_NAME, 'IsIdentity') = 1

    -- Nếu có cột Identity
    IF @IdentityColumn IS NOT NULL
    BEGIN
        -- Tắt kiểm tra Identity
        SET @sql = 'SET IDENTITY_INSERT ['+@TargetDb+'].[' + @SchemaName + '].[' + @TableName + '] ON;'

        -- Lấy danh sách các cột (loại trừ Identity)
        SELECT @ColumnList = COALESCE(@ColumnList + ', ', '') + COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = @SchemaName 
          AND TABLE_NAME = @TableName
          AND COLUMNPROPERTY(OBJECT_ID(TABLE_SCHEMA + '.' + TABLE_NAME), COLUMN_NAME, 'IsIdentity') = 0

        -- Ghép câu INSERT
        SET @sql = @sql + CHAR(13) +
        'INSERT INTO ['+@TargetDb+'].[' + @SchemaName + '].[' + @TableName + '] (' + @ColumnList + ')' + CHAR(13) +
        'SELECT ' + @ColumnList + CHAR(13) +
        'FROM [' + @SourceSvr + '].[' + @SourceDb + '].[' + @SchemaName + '].[' + @TableName + '] TOP ('+@nrow+');' + CHAR(13) +
        'SET IDENTITY_INSERT ['+@TargetDb+'].[' + @SchemaName + '].[' + @TableName + '] OFF;'

        BEGIN TRY
            EXEC sp_executesql @sql
            PRINT 'Successfully copied data for table: ' + @SchemaName + '.' + @TableName
        END TRY
        BEGIN CATCH
            PRINT 'Error in table ' + @SchemaName + '.' + @TableName + ': ' + ERROR_MESSAGE()
        END CATCH

        -- Reset biến
        SET @ColumnList = NULL
        SET @IdentityColumn = NULL
    END
    ELSE
    BEGIN
        -- Nếu không có cột Identity, thực hiện insert bình thường
        SET @sql = 
        'INSERT INTO ['+@TargetDb+'].[' + @SchemaName + '].[' + @TableName + '] ' + CHAR(13) +
        'SELECT TOP 1000 * FROM [' + @SourceSvr + '].[' + @SourceDb + '].[' + @SchemaName + '].[' + @TableName + '];'

        BEGIN TRY
            EXEC sp_executesql @sql
            PRINT 'Successfully copied data for table: ' + @SchemaName + '.' + @TableName
        END TRY
        BEGIN CATCH
            PRINT 'Error in table ' + @SchemaName + '.' + @TableName + ': ' + ERROR_MESSAGE()
        END CATCH
    END

    FETCH NEXT FROM table_cursor 
    INTO @SchemaName, @TableName
END

CLOSE table_cursor
DEALLOCATE table_cursor

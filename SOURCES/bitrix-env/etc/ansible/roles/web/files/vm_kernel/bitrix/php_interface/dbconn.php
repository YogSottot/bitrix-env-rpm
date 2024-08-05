<?php
$DBDebug = false;
$DBDebugToFile = false;

// need for old distros
define('CACHED_b_lang', 3600);
define('CACHED_b_agent', 3600);
define('CACHED_b_lang_domain', 3600);

define("BX_FILE_PERMISSIONS", 0644);
define("BX_DIR_PERMISSIONS", 0755);
@umask(~(BX_FILE_PERMISSIONS|BX_DIR_PERMISSIONS)&0777);

define("BX_UTF", true);
define("MYSQL_TABLE_TYPE", "INNODB");
define("BX_DISABLE_INDEX_PAGE", true);

define("BX_TEMPORARY_FILES_DIRECTORY", "/home/bitrix/.bx_temp/__DBNAME__/");
define("BX_CRONTAB_SUPPORT", true);

define("SHORT_INSTALL", true);
define("VM_INSTALL", true);

#!/usr/bin/php
#
# Minimal Sphinx configuration for Bitrix
#
# Include site search db
<?php


print_r($args);
exit();

include '/home/bitrix/www/bitrix/php_interface/dbconn.php';
echo $DBType."
";
echo $DBHost."
";
echo $DBLogin."
";
echo $DBName."
";
if(defined('BX_UTF') && BX_UTF === true)
{
    echo "utf8
";
}
else
{
    echo "cp1251
";
}
echo $DBPassword."
";

exit();
?>

<?
$_SERVER["DOCUMENT_ROOT"] = '/home/bitrix/www';
$DOCUMENT_ROOT = $_SERVER["DOCUMENT_ROOT"];
define("LANGUAGE_ID", "en");
define("NO_KEEP_STATISTIC", true);
define("NOT_CHECK_PERMISSIONS",true);
define('BX_NO_ACCELERATOR_RESET', true);
require('/root/bitrix-env/tmp/db_connect.php');

$dbconn = $_SERVER['DOCUMENT_ROOT']."/bitrix/php_interface/dbconn.php";
if(file_exists($dbconn))
{
	include($dbconn);
	$arFile = file($dbconn);
	foreach($arFile as $line)
	{
		if (preg_match("#^[ \t]*".'\$'."(DB[a-zA-Z]+)#",$line,$regs))
		{
			$setNewVal = false;
			$key = $regs[1];
			switch($key)
			{
				case 'DBHost':
					$new_val = $dbHost;
					$setNewVal = true;
					break;
				case 'DBPassword':
					$new_val = $dbPasswd;
					$setNewVal = true;
					break;
				case 'DBName':
					$new_val = $dbName;
					$setNewVal = true;
					break;
			}
			if (isset($new_val) && $$key != $new_val && $setNewVal)
			{
				$strFile.='#'.$line.
				'$'.$key.' = "'.addslashes($new_val).'";'."\n\n";
			}
			else
				$strFile.=$line;
			}
		else
			$strFile.=$line;
	}

	$f = fopen($dbconn,"wb");
	fputs($f,$strFile);
	fclose($f);
}
require($_SERVER["DOCUMENT_ROOT"]."/bitrix/modules/main/include/prolog_before.php");
if(file_exists("/root/bitrix-env/tmp/memcache_node_list.php") && CModule::IncludeModule('cluster'))
{
	require("/root/bitrix-env/tmp/memcache_node_list.php");
	foreach($memcacheList as $memcacheNode)
	{
		$ob = new CClusterMemcache;
		$arFields = array(
			"HOST" => $memcacheNode,
			"PORT" => 11211,
			"WEIGHT" => 50,
			"GROUP_ID" => 1
		);
		$res = $ob->Add($arFields);
		if(intval($res) > 0)
			$ob->Update($res, array('STATUS' => 'ONLINE'));
	}

}
?>

<?

$_SERVER["DOCUMENT_ROOT"] = '/home/bitrix/www/';
$DOCUMENT_ROOT = $_SERVER["DOCUMENT_ROOT"];
define("NO_KEEP_STATISTIC", true);
define("NOT_CHECK_PERMISSIONS",true);
define('BX_NO_ACCELERATOR_RESET', true);
require($_SERVER["DOCUMENT_ROOT"]."/bitrix/modules/main/include/prolog_before.php");
require('/root/bitrix-env/tmp/db_connect.php');

CModule::IncludeModule('cluster');

$obNode = new CClusterDBNode;
$node_id = $obNode->Add(array(
    "ACTIVE" => "Y",
	"ROLE_ID" => "SLAVE",
	"NAME" => $dbHost,
	"DESCRIPTION" => false,
	"DB_HOST" => $dbHost,
	"DB_NAME" => $dbName,
	"DB_LOGIN" => 'root',
	"DB_PASSWORD" => $dbPasswd,
	"MASTER_ID" => 1,
	"MASTER_HOST" => $masterHost,
	"MASTER_PORT" => 3306,
	"SERVER_ID" => false,
	"STATUS" => "ONLINE",
	"SELECTABLE" => "Y",
	"WEIGHT" => 100,
	"GROUP_ID" => 1
));
echo "Add claster db node: ".(intval($node_id) > 0 ? "Ok" : "Error")."
";

$ob = new CClusterWebnode;
$arFields = array(
	"NAME" => $dbHost,
	"HOST" => $dbHost,
	"PORT" => 80,
	"STATUS_URL" => '/server-status',
	"DESCRIPTION" => $dbHost,
	"GROUP_ID" => 1
);
$res = $ob->Add($arFields);
echo "Add claster webnode: ".(intval($res) > 0 ? "Ok" : "Error")."
";

$ob = new CClusterMemcache;
$arFields = array(
	"HOST" => $dbHost,
	"PORT" => 11211,
	"WEIGHT" => 50,
	"GROUP_ID" => 1
);
$res = $ob->Add($arFields);
if(intval($res) > 0)
{
	$ob->Update($res, array('STATUS' => 'ONLINE'));
}
echo "Add claster memcache node: ".(intval($res) > 0 ? "Ok" : "Error")."
";

?>

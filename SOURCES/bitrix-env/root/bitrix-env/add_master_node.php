<?

$_SERVER["DOCUMENT_ROOT"] = '/home/bitrix/www/';
$DOCUMENT_ROOT = $_SERVER["DOCUMENT_ROOT"];
define("NO_KEEP_STATISTIC", true);
define("NOT_CHECK_PERMISSIONS",true);
define('BX_NO_ACCELERATOR_RESET', true);
require($_SERVER["DOCUMENT_ROOT"]."/bitrix/modules/main/include/prolog_before.php");
require('/root/bitrix-env/tmp/db_connect.php');

$dbSession = COption::GetOptionString("security", "session", "N");
if($dbSession != 'Y')
{
	CModule::IncludeModule('security');
	COption::SetOptionString("security", "session", "Y");
	CSecuritySession::Init();
	CAgent::RemoveAgent("CSecuritySession::CleanUpAgent();", "security");
	CAgent::Add(array(
		"NAME"=>"CSecuritySession::CleanUpAgent();",
		"MODULE_ID"=>"security",
		"ACTIVE"=>"Y",
		"AGENT_INTERVAL"=>1800,
		"IS_PERIOD"=>"N",
	));
	
	echo "Store session on db: Ok
";
}

CModule::IncludeModule('cluster');

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
echo "Add claster mamcache: ".(intval($res) > 0 ? "Ok" : "Error")."
";

?>

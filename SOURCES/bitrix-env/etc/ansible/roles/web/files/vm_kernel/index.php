<?php
error_reporting(E_ALL & ~E_NOTICE);
header("Content-type: text/html; charset=utf-8");

$lang = '';

if (isset($_REQUEST['lang']))
{
	$lang = $_REQUEST['lang'];

	if (!in_array($lang, ['ru', 'en', 'de']))
	{
		$lang = 'en';
	}
}
elseif (@preg_match('#ru#i', $_SERVER['HTTP_ACCEPT_LANGUAGE'] ?? ''))
{
	$lang = 'ru';
}
elseif (@preg_match('#de#i', $_SERVER['HTTP_ACCEPT_LANGUAGE'] ?? ''))
{
	$lang = 'de';
}
else
{
	$lang = 'en';
}

define("LANG", $lang);

if (LANG == 'ru')
{
	$msg = [
		'hello' => "Добро пожаловать!",
		'title' => "Добро пожаловать<br>в виртуальную машину VMBitrix!",
		'desc' => "Система оптимально сконфигурирована и готова к использованию<br>\"1С-Битрикс: Управление сайтом\", \"1С-Битрикс: Энтерпрайз\" и \"1С-Битрикс24\".",
		'setup_text' => "С помощью скрипта <a href=\"https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=32&LESSON_ID=4891\" target=\"_blank\">BitrixSetup</a> загрузите дистрибутив пробной или коммерческой версии продукта непосредственно на ваш сервер.",
		'restore_text' => "Для восстановления копии проекта из бекапа скачайте и разместите в корне сайта скрипт <a href=\"https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=32&CHAPTER_ID=02014&LESSON_PATH=3903.4862.4894.2014\" target=\"_blank\">Restore</a>.",
	];
}
elseif (LANG == 'de')
{
	$msg = [
		'hello' => "Willkommen!",
		'title' => "Herzlich willkommen<br/>bei der virtuellen Maschine VMBitrix!",
		'desc' => "Das System ist fur die Verwendung von Bitrix24 optimal konfiguriert und einsatzbereit\".",
		'setup_text' => "Use <a href=\"https://training.bitrix24.com/support/training/course/?COURSE_ID=58&LESSON_ID=13736&LESSON_PATH=5455.5464.13736\" target=\"_blank\">BitrixSetup</a> script to upload the commercial or trial version of Bitrix24 directly to your web server.",
		'restore_text' => "Um eine Kopie des Projekts aus einem Backup wiederherzustellen, laden Sie die Datei <a href=\"https://training.bitrix24.com/support/training/course/?COURSE_ID=58&LESSON_ID=5913&LESSON_PATH=5455.5489.5913\" target=\"_blank\">Restore</a> herunter und platzieren Sie sie im Stammverzeichnis der Site.",
	];
}
else
{
	$msg = [
		'hello' => "Welcome!",
		'title' => "Welcome to<br>Bitrix Virtual Appliance!",
		'desc' => "System is optimally configured and is ready to be used with Bitrix24.",
		'setup_text' => "Use <a href=\"https://training.bitrix24.com/support/training/course/?COURSE_ID=58&LESSON_ID=13736&LESSON_PATH=5455.5464.13736\" target=\"_blank\">BitrixSetup</a> script to upload the commercial or trial version of Bitrix24 directly to your web server.",
		'restore_text' => "To restore a copy of a project from a backup download and place <a href=\"https://training.bitrix24.com/support/training/course/?COURSE_ID=58&LESSON_ID=5913&LESSON_PATH=5455.5489.5913\" target=\"_blank\">Restore</a> in the root of the site.",
	];
}
?>
<!DOCTYPE html>
<html lang="<?= $lang ?>">
<head>
	<title><?= $msg['hello'] ?></title>
	<style>
        html,
        body {
            padding: 0 10px;
            margin: 0;
            background: #2fc6f7;
            position: relative;
            font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
            font-size: 16px;
        }

        .wrap {
            min-height: 100vh;
            position: relative;
        }

        .cloud {
            background-size: contain;
            position: absolute;
            z-index: 1;
            background-repeat: no-repeat;
            background-position: center;
            opacity: .8;
        }

        .cloud-fill {
            background-image: url(data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxMDEiIGhlaWdodD0iNjMiIHZpZXdCb3g9IjAgMCAxMDEgNjMiPiAgPHBhdGggZmlsbD0iI0U0RjhGRSIgZmlsbC1ydWxlPSJldmVub2RkIiBkPSJNNDc3LjM5MjY1MywyMTEuMTk3NTYyIEM0NzYuNDcwMzYyLDIwMS41NDc2MjIgNDY4LjM0NDA5NywxOTQgNDU4LjQ1MjIxNCwxOTQgQzQ1MC44MTI2NzksMTk0IDQ0NC4yMjc3NzcsMTk4LjUwNDA2MyA0NDEuMTk5MDYzLDIwNC45OTk1NzkgQzQzOS4xNjkwNzYsMjA0LjI2MTQzMSA0MzYuOTc4NjM2LDIwMy44NTc3NzEgNDM0LjY5MzQzOSwyMDMuODU3NzcxIEM0MjQuMTgzMTE2LDIwMy44NTc3NzEgNDE1LjY2Mjk4MywyMTIuMzc3NTg4IDQxNS42NjI5ODMsMjIyLjg4NzkxMSBDNDE1LjY2Mjk4MywyMjMuMzg1MDY0IDQxNS42ODc5MzUsMjIzLjg3NjIxNSA0MTUuNzI1MjA2LDIyNC4zNjM4OTIgQzQxNC40NjU1ODUsMjI0LjA0OTYxOCA0MTMuMTQ4NDc4LDIyMy44ODA2MzcgNDExLjc5MTU3MywyMjMuODgwNjM3IEM0MDIuODMxNzczLDIyMy44ODA2MzcgMzk1LjU2ODczNCwyMzEuMTQzNjc2IDM5NS41Njg3MzQsMjQwLjEwMzQ3NiBDMzk1LjU2ODczNCwyNDkuMDYyOTYxIDQwMi44MzE3NzMsMjU2LjMyNiA0MTEuNzkxNTczLDI1Ni4zMjYgTDQ3Mi4zMTg0NzUsMjU2LjMyNiBDNDg0LjkzODM4LDI1Ni4zMjYgNDk1LjE2ODU0MSwyNDYuMDk1MjA3IDQ5NS4xNjg1NDEsMjMzLjQ3NTYxOCBDNDk1LjE2ODU0MSwyMjIuNjAwNDg1IDQ4Ny41Njk0MzUsMjEzLjUwNjQ0NyA0NzcuMzkyNjUzLDIxMS4xOTc1NjIiIHRyYW5zZm9ybT0idHJhbnNsYXRlKC0zOTUgLTE5NCkiIG9wYWNpdHk9Ii41Ii8+PC9zdmc+);
        }

        .cloud-border {
            background-image: url(data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxODUiIGhlaWdodD0iMTE3IiB2aWV3Qm94PSIwIDAgMTg1IDExNyI+ICA8cGF0aCBmaWxsPSJub25lIiBzdHJva2U9IiNFNEY4RkUiIHN0cm9rZS13aWR0aD0iMyIgZD0iTTEwODIuNjk2MzcsNTI5LjI1MjY1NyBDMTA4MS4wMjAzMSw1MTEuNzE2MDg3IDEwNjYuMjUyNjcsNDk4IDEwNDguMjc2NDMsNDk4IEMxMDM0LjM5MzMxLDQ5OCAxMDIyLjQyNjc0LDUwNi4xODUxMSAxMDE2LjkyMjc1LDUxNy45ODkyMzQgQzEwMTMuMjMzNzEsNTE2LjY0NzgxNyAxMDA5LjI1MzA4LDUxNS45MTQyNTcgMTAwNS4xMDAyNSw1MTUuOTE0MjU3IEM5ODYuMDAwMTMzLDUxNS45MTQyNTcgOTcwLjUxNjcyOCw1MzEuMzk3MDg4IDk3MC41MTY3MjgsNTUwLjQ5NzIwOSBDOTcwLjUxNjcyOCw1NTEuNDAwNjcxIDk3MC41NjIwNzMsNTUyLjI5MzIyNyA5NzAuNjI5ODA0LDU1My4xNzk0NjkgQzk2OC4zNDA3MjksNTUyLjYwODM0OCA5NjUuOTQ3MTg2LDU1Mi4zMDEyNjMgOTYzLjQ4MTMyMiw1NTIuMzAxMjYzIEM5NDcuMTk4OTIxLDU1Mi4zMDEyNjMgOTM0LDU2NS41MDAxODQgOTM0LDU4MS43ODI1ODQgQzkzNCw1OTguMDY0NDExIDk0Ny4xOTg5MjEsNjExLjI2MzMzMiA5NjMuNDgxMzIyLDYxMS4yNjMzMzIgTDEwNzMuNDc1Miw2MTEuMjYzMzMyIEMxMDk2LjQwOTAxLDYxMS4yNjMzMzIgMTExNSw1OTIuNjcxMTkyIDExMTUsNTY5LjczNzk1OSBDMTExNSw1NDkuOTc0ODc4IDExMDEuMTkwMzUsNTMzLjQ0ODUzMSAxMDgyLjY5NjM3LDUyOS4yNTI2NTciIHRyYW5zZm9ybT0idHJhbnNsYXRlKC05MzIgLTQ5NikiIG9wYWNpdHk9Ii41Ii8+PC9zdmc+);
        }

        .cloud-1 {
            top: 9%;
            left: 50%;
            width: 60px;
            height: 38px;
        }

        .cloud-2 {
            top: 14%;
            left: 12%;
            width: 80px;
            height: 51px;
        }

        .cloud-3 {
            top: 11%;
            right: 14%;
            width: 106px;
            height: 67px;
        }

        .cloud-4 {
            top: 33%;
            right: 13%;
            width: 80px;
            height: 51px;
        }

        .cloud-5 {
            bottom: 23%;
            right: 12%;
            width: 80px;
            height: 51px;
        }

        .cloud-6 {
            bottom: 23%;
            left: 12%;
            width: 80px;
            height: 51px;
        }

        .cloud-7 {
            top: 13%;
            left: 6%;
            width: 60px;
            height: 31px;
            opacity: 1;
        }

        .cloud-8 {
            top: 43%;
            right: 6%;
            width: 86px;
            height: 54px;
            opacity: 1;
        }

        .header {
            min-height: 220px;
            max-width: 727px;
            margin: 0 auto;
            box-sizing: border-box;
            position: relative;
            z-index: 10;
        }

        .buslogo-link {
            position: absolute;
            top: 50%;
            margin-top: -23px;
        }

        .buslogo {
            width: 255px;
            display: block;
            height: 46px;
            background-repeat: no-repeat;
        }

        .wrap.en .buslogo,
        .wrap.de .buslogo {
            background-image: url(data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI5OS42NTYiIGhlaWdodD0iMzMuNzUiIHZpZXdCb3g9IjAgMCA5OS42NTYgMzMuNzUiPiAgPGRlZnM+ICAgIDxzdHlsZT4gICAgICAuY2xzLTEgeyAgICAgICAgZmlsbDogI2ZmZjsgICAgICAgIGZpbGwtcnVsZTogZXZlbm9kZDsgICAgICB9ICAgIDwvc3R5bGU+ICA8L2RlZnM+ICA8cGF0aCBpZD0iQml0cml4X2NvcHkiIGRhdGEtbmFtZT0iQml0cml4IGNvcHkiIGNsYXNzPSJjbHMtMSIgZD0iTTE4MS4wMTQsMTE3LjMxNGgxMC4xMzVjNy4zNDgsMCwxMS4xLTQuNDY3LDExLjEtOS4zNjZhNy42MjEsNy42MjEsMCwwLDAtNS45NTYtNy42Mzd2LTAuMWE3LjEzLDcuMTMsMCwwLDAsMy44NDMtNi41MzJjMC00LjEzMS0zLjA3NC04LjAyMS05Ljg0Ny04LjAyMWgtOS4yN3YzMS42NTNabTUuNzY0LTQuNzU1di04LjkzNEgxOTEuMWMzLjIxOCwwLDUuMjgzLDEuNjMzLDUuMjgzLDQuMzIzLDAsMy4yMTgtMi4wNjUsNC42MTEtNS45MDgsNC42MTFoLTMuN1ptMC0xMy42ODlWOTAuNDE2aDIuNjljMy40NTgsMCw0Ljk0NywxLjg3Myw0Ljk0Nyw0LjIyNywwLDIuNDUtMS42ODEsNC4yMjctNC45LDQuMjI3aC0yLjczOFptMTkuMjQ5LDE4LjQ0NGg1Ljc2NFY5NC42aC01Ljc2NHYyMi43MTlaTTIwOC45MDksOTAuOWEzLjQzNSwzLjQzNSwwLDEsMC0zLjUwNi0zLjQxQTMuMzg2LDMuMzg2LDAsMCwwLDIwOC45MDksOTAuOVptMTUuODQ2LDI2LjlhMTIuOTkyLDEyLjk5MiwwLDAsMCw2LjYyOS0xLjc3N2wtMS43My0zLjkzOGE2LjQyOSw2LjQyOSwwLDAsMS0zLjQ1OCwxLjFjLTEuNDg5LDAtMi4yMDktLjc2OC0yLjIwOS0yLjg4MlY5OS4wNjJoNS40NzVsMS4zOTMtNC40NjdoLTYuODY4Vjg3LjYzMWwtNS43MTYsMS42ODFWOTQuNmgtNC4wODN2NC40NjdoNC4wODN2MTIuNjMyQzIxOC4yNzEsMTE1LjQ4OSwyMjAuNzIsMTE3Ljc5NCwyMjQuNzU1LDExNy43OTRabTguNjM4LS40OGg1LjcxNlYxMDEuMjcyYzEuODczLTEuNjM0LDMuMTIyLTIuMjU4LDQuNjExLTIuMjU4YTQuODU2LDQuODU2LDAsMCwxLDIuNTk0Ljc2OWwyLjAxNy00Ljg1MWE1Ljk0Nyw1Ljk0NywwLDAsMC0zLjIxOC0uOTEzYy0yLjMwNiwwLTQuMTc5LDEuMDU3LTYuMjQ0LDMuMTIyTDIzOC4yNDQsOTQuNmgtNC44NTF2MjIuNzE5Wm0xNi40NjgsMGg1Ljc2NFY5NC42aC01Ljc2NHYyMi43MTlaTTI1Mi43NDMsOTAuOWEzLjQzNSwzLjQzNSwwLDEsMC0zLjUwNi0zLjQxQTMuMzg2LDMuMzg2LDAsMCwwLDI1Mi43NDMsOTAuOVptNC44NDcsMjYuNDE3aDZsNS41NzItNy41ODksNS40NzUsNy41ODloNmwtOC40LTExLjQzMUwyODAuNTQ5LDk0LjZoLTUuOTU2bC01LjM3OSw3LjQtNS4zMzItNy40aC02bDguMjE0LDExLjI4OFoiIHRyYW5zZm9ybT0idHJhbnNsYXRlKC0xODEgLTg0LjAzMSkiLz48L3N2Zz4=);
        }

        .wrap.ru .buslogo {
            background-image: url(data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyMzAuNjU2IiBoZWlnaHQ9IjQzLjMxMyIgdmlld0JveD0iMCAwIDIzMC42NTYgNDMuMzEzIj4gIDxkZWZzPiAgICA8c3R5bGU+ICAgICAgLmNscy0xIHsgICAgICAgIGZpbGw6ICNmZmY7ICAgICAgICBmaWxsLXJ1bGU6IGV2ZW5vZGQ7ICAgICAgfSAgICA8L3N0eWxlPiAgPC9kZWZzPiAgPHBhdGggaWQ9Il8xQy3QkdC40YLRgNC40LrRgSIgZGF0YS1uYW1lPSIxQy3QkdC40YLRgNC40LrRgSIgY2xhc3M9ImNscy0xIiBkPSJNMTg3Ljg4MiwxMTcuMzE0aDUuNjY4Vjg1LjQyMWgtNC4zNzFsLTEwLjU2Nyw0LjgsMS45MjIsNC40NjcsNy4zNDgtMy4zMTR2MjUuOTM3Wm0zNi40LTYuNThhMTQuOTQ2LDE0Ljk0NiwwLDAsMS03Ljc4MSwyLjIwOWMtNi40ODQsMC0xMC41MTktNC42MTEtMTAuNTE5LTExLjIzOSwwLTYuMiwzLjctMTEuNDgsMTAuNzExLTExLjQ4YTE3LjAxNiwxNy4wMTYsMCwwLDEsOC4xNjUsMi4wNjVWODYuOTFhMjEuMTYxLDIxLjE2MSwwLDAsMC04LjMwOS0xLjUzN2MtMTAuMTgzLDAtMTYuNzE1LDcuMy0xNi43MTUsMTYuNDc1LDAsOS4yNyw1LjYyLDE1Ljk0NiwxNS45OTQsMTUuOTQ2YTIwLjI3NCwyMC4yNzQsMCwwLDAsMTAuMDM5LTIuNVptNC40NTUtMi45M0gyNDEuMzdWMTAzSDIyOC43Mzd2NC44Wm0yMy41NzcsNC43NTV2LTkuOTQzaDIuNGExMC41NjksMTAuNTY5LDAsMCwxLDUuMTM5Ljk2MSw0LjI0Miw0LjI0MiwwLDAsMSwyLjAxNyw0LjAzNWMwLDMuMzYyLTIuMDY1LDQuOTQ3LTYuNzcyLDQuOTQ3aC0yLjc4NlptLTUuODEyLDQuNzU1aDguNDU0YzkuMzY2LDAsMTIuNzc2LTQuMTMxLDEyLjc3Ni05Ljg0NiwwLTMuODkxLTEuNjMzLTYuNDg1LTQuNDY3LTcuOTc0LTIuMjU3LTEuMi01LjE4Ny0xLjU4NS04LjY0NS0xLjU4NWgtMi4zMDZWOTAuMzY4aDEyLjY4bDEuNTM3LTQuNzA3SDI0Ni41djMxLjY1M1ptMjUuMDYyLDBoNS41NzFsNy4xMDktMTAuMjMxYzEuMzQ1LTEuOTIxLDIuNC0zLjcsMy4wMjYtNC43NTVoMC4xYy0wLjEsMS4zNDUtLjE5MiwzLjA3NC0wLjE5Miw0Ljl2MTAuMDg3aDUuNjJWOTQuNmgtNS41NzJsLTcuMTA5LDEwLjIzMWMtMS4zLDEuOTIxLTIuNCwzLjctMy4wMjYsNC43NTVoLTAuMWMwLjEtMS4zNDUuMTkyLTMuMDc0LDAuMTkyLTQuOVY5NC42aC01LjYxOXYyMi43MTlabTMwLjg3MywwaDUuNzE2Vjk5LjM1aDYuNzI1bDEuNDg5LTQuNzU1SDI5NS41MjFWOTkuMzVoNi45MTZ2MTcuOTY0Wk0zMTguNDIzLDEyOC43aDUuNzE2VjExNy4yNjZhMTIuMTU1LDEyLjE1NSwwLDAsMCwzLjUwNi41MjhjNy4xMDksMCwxMS44MTYtNC45NDcsMTEuODE2LTExLjkxMSwwLTcuMjUzLTQuMjc1LTExLjg2NC0xMi40NC0xMS44NjRhMjYuNjQsMjYuNjQsMCwwLDAtOC42LDEuNDQxVjEyOC43Wm01LjcxNi0xNi4yMzVWOTkuMTFhOS41NzQsOS41NzQsMCwwLDEsMi42OS0uMzg0YzQuMDgyLDAsNi43NzIsMi4zMDUsNi43NzIsNy4xNTcsMCw0LjM3LTIuMTYxLDcuMTU2LTYuMzg4LDcuMTU2QTcuOTcsNy45NywwLDAsMSwzMjQuMTM5LDExMi40NjNabTE4LjY3NCw0Ljg1MWg1LjU3Mmw3LjEwOS0xMC4yMzFjMS4zNDUtMS45MjEsMi40LTMuNywzLjAyNi00Ljc1NWgwLjFjLTAuMSwxLjM0NS0uMTkyLDMuMDc0LTAuMTkyLDQuOXYxMC4wODdoNS42MTlWOTQuNmgtNS41NzFsLTcuMTA5LDEwLjIzMWMtMS4zLDEuOTIxLTIuNCwzLjctMy4wMjYsNC43NTVoLTAuMWMwLjEtMS4zNDUuMTkyLTMuMDc0LDAuMTkyLTQuOVY5NC42aC01LjYydjIyLjcxOVptMjUuNjg3LDBoNS43MTZWMTA3LjloMy40MWMwLjY3MiwwLDEuMy42MjQsMS45NjksMi4xNjFsMi44ODIsNy4yNTNoNi4ybC00LjEzLTguNjk0YTQuODc4LDQuODc4LDAsMCwwLTIuNjQyLTIuNzg1di0wLjFjMS45MjEtMS4xNTIsMi4xMTMtNC40MTgsMy4yNjYtNmExLjkxOSwxLjkxOSwwLDAsMSwxLjU4NS0uNzIxLDMuODU4LDMuODU4LDAsMCwxLDEuMy4xOTJWOTQuMzU1YTguMiw4LjIsMCwwLDAtMi4zNTQtLjMzNiw0LjgwOSw0LjgwOSwwLDAsMC00LjE3OCwyLjAxN2MtMS44NzQsMi43MzgtMS44MjYsNy40OTMtNC42Niw3LjQ5M2gtMi42NDFWOTQuNkgzNjguNXYyMi43MTlabTMyLjk4OCwwLjQ4YTE0LjIxNCwxNC4yMTQsMCwwLDAsNy43ODEtMi4yMDlsLTEuNjgxLTMuOTM5YTEwLjQ4OCwxMC40ODgsMCwwLDEtNS4yODMsMS41MzdjLTMuODkxLDAtNi40MzctMi41NDUtNi40MzctNy4yLDAtNC4xNzksMi41LTcuMzQ5LDYuNzI1LTcuMzQ5YTguOTQyLDguOTQyLDAsMCwxLDUuNTIzLDEuNzc3Vjk1LjU1NmExMS40MzMsMTEuNDMzLDAsMCwwLTYuMS0xLjUzNywxMS43NDEsMTEuNzQxLDAsMCwwLTEyLjAwOCwxMi4xQzM5MC4wMDgsMTEyLjcsMzk0LjA5MSwxMTcuNzk0LDQwMS40ODgsMTE3Ljc5NFoiIHRyYW5zZm9ybT0idHJhbnNsYXRlKC0xNzguNjI1IC04NS4zNzUpIi8+PC9zdmc+);
        }

        .content {
            z-index: 10;
            position: relative;
            margin-bottom: 20px;
        }

        .content-container {
            z-index: 10;
            max-width: 727px;
            margin: 0 auto;
            padding: 28px 25px 25px;
            border-radius: 11px;
            box-shadow: 0 4px 20px 0 rgba(6, 54, 70, .15);
            box-sizing: border-box;
            text-align: center;
            background-color: #fff;
            position: relative;
        }

        .content-block {
            position: relative;
            z-index: 10;
        }

        h2.content-header {
            color: #2fc6f7;
            font: 400 27px/27px "Helvetica Neue", Helvetica, Arial, sans-serif;
            margin-bottom: 13px;
            margin-top: 31px;
        }

        .lang {
            vertical-align: middle;
            text-align: left;
            box-sizing: border-box;
            color: #333;
            font: 12px/22px "Helvetica Neue", Helvetica, Arial, sans-serif;
            display: block;
            text-decoration: none;
            padding: 5px 5px 5px 35px;
        }

        .lang:after {
            background: no-repeat center url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAzCAMAAACpFXjLAAAAk1BMVEX///8TLa4TLq4ULq8bQOccQOc4N2A4N2FAP2VAQGZNTYBOToBOToFXV4dXWIdYWIdYWIhZW4paW4paW4thYY9iYo9iYpCPJR6QJR6uJRKvJRKvJhO/v7/AngDAnwDAwMDBMyzBMy3BNC3CNC3nNRfnNhfnNhjp6O7p6e/p6fD9/f3+/v7/0gD/0wD/1AD///8wMDDKTuTrAAAAAXRSTlMAQObYZgAAARRJREFUeNqtkGFvgyAQhk+n1lW7OV2rRVmFKtoBdv//1+3ARKf2U7PnuDfh8UJyQmW5jAcLLlLK+9wVVPL+h5VAKnA8z8djG8MFxzdmwoEXH+/W+KbthGWUKIgQjRCibRvRYhEgbWtVY4QQJU7gt3HKmDOUhJwJRoltgA1BGIS71yDI8yIvMCDsjt2pS/ZypIJdlnwk6SHmhisvIHjvT/3n7TBtG7xlSZpk8ZXVnDNm3+iPtySaJ9I426dRxGvGasbz7R8rmHmcMyzETsx8y4cTK2CDuwJcb8H/CDosoA+E1oPWJgYMhULpAS/mhmGEVlorxKZGQekXtTEmbPhZ8YwoxILiGUHVAmqFVtMyRszLIdvlfgFLUlmfWPoXcwAAAABJRU5ErkJggg==);
            content: '';
            display: block;
            width: 16px;
            height: 12px;
            position: absolute;
            top: 50%;
            left: 12px;
            margin-top: -6px;
        }

        .lang.ru:after {
            background-position: 0 0;
        }

        .lang.en:after {
            background-position: 0 -13px;
        }

        .lang.de:after {
            background-position: 0 -39px;
        }

        .select-container {
            border: 2px solid #d5dde0;
            height: 32px;
            width: 50px;
            border-radius: 2px;
			display: inline-block;
        }

		.links-container {
			display: flex;
			flex-flow: row nowrap;
			gap: 20px;
			padding: 20px 0 10px;
			text-align: left;
        }

		.links-item {
			display: inline-block;
			padding: 12px;
			width: 50%;
            border-radius: 8px;
			border: 2px solid #d5dde0;
            font-size: 15px;
        }

		.languages-container {
			margin-top: 20px;
			text-align: right;
        }

        .select-container > .select-block,
        .selected-lang {
            width: 100%;
            display: block;
            height: 32px;
            position: relative;
            cursor: pointer;
        }

        .selected-lang:before {
            content: '';
            border: 4px solid #fff;
            border-top: 4px solid #7e939b;
            display: block;
            position: absolute;
            right: 8px;
            top: 15px;
        }

        .selected-lang:after {
            left: 11px;
        }

        .select-popup {
            display: none;
            position: absolute;
            top: 100%;
            z-index: 100;
            min-width: 100px;
            border-radius: 2px;
            padding: 5px 0;
            background-color: #fff;
            box-shadow: 0 5px 5px rgba(0, 0, 0, .4);
        }

        .select-lang-item {
            height: 32px;
            width: 100%;
            position: relative;
            padding: 0 10px;
            box-sizing: border-box;
            transition: 220ms all ease;
        }

        .select-lang-item:hover {
            background-color: #f3f3f3;
        }
	</style>
</head>
<body>
<div class="wrap <?= LANG ?>">
	<header class="header">
		<a href="" target="_blank" class="buslogo-link"><span class="buslogo <?= LANG ?>"></span></a>
	</header>
	<section class="content">
		<div class="content-container">
			<div class="cloud-layer">
				<div class="cloud cloud-7 cloud-fill"></div>
				<div class="cloud cloud-8 cloud-border"></div>
			</div>
			<div class="content-block">
				<h2 class="content-header" style="color: #000;margin: 46px 0 30px;"><?= $msg['title'] ?></h2>
				<p><?= $msg['desc'] ?></p>
				<div class="links-container">
					<div class="links-item"><?= $msg['setup_text'] ?></div>
					<div class="links-item"><?= $msg['restore_text'] ?></div>
				</div>
				<div class="languages-container">
					<div class="select-container"
						 onclick="document.getElementById('lang-popup').style.display = document.getElementById('lang-popup').style.display == 'block' ? 'none' : 'block'">
						<span class="selected-lang lang <?= $lang ?>"></span>
						<div class="select-popup" id="lang-popup">
							<?php
							foreach (['en', 'de', 'ru'] as $l)
							{
								?>
								<div class="select-lang-item">
									<a href="?lang=<?= $l ?>" class="lang <?= $l ?>"><?= $l ?></a>
								</div>
								<?php
							}
							?>
						</div>
					</div>
				</div>
			</div>
		</div>
	</section>
	<div class="cloud-layer">
		<div class="cloud cloud-1 cloud-fill"></div>
		<div class="cloud cloud-2 cloud-border"></div>
		<div class="cloud cloud-3 cloud-border"></div>
		<div class="cloud cloud-4 cloud-border"></div>
		<div class="cloud cloud-5 cloud-border"></div>
		<div class="cloud cloud-6 cloud-border"></div>
	</div>
</div>
</body>
</html>

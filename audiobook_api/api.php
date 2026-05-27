<?php
/**
 * GT听书 API - 有声书目录接口
 * 
 * 用法:
 *   GET api.php?action=books              → 返回书单
 *   GET api.php?action=chapters&book=三体 → 返回某书的章节列表
 * 
 * 将本文件放在有声书根目录下，或修改 $bookRoot 指向有声书目录。
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');

// 有声书根目录（修改为你的实际路径）
$bookRoot = __DIR__;

$action = $_GET['action'] ?? '';

switch ($action) {
    case 'books':
        $books = [];
        $items = scandir($bookRoot);
        foreach ($items as $item) {
            if ($item[0] === '.') continue;
            if (is_dir("$bookRoot/$item")) {
                // 检测是否有封面图片
                $cover = '';
                foreach (['cover.jpg', 'cover.png', 'cover.jpeg', 'folder.jpg'] as $c) {
                    if (file_exists("$bookRoot/$item/$c")) {
                        $cover = "$item/$c";
                        break;
                    }
                }
                $books[] = [
                    'name' => $item,
                    'cover' => $cover,
                ];
            }
        }
        // 按书名排序
        usort($books, fn($a, $b) => strcmp($a['name'], $b['name']));
        echo json_encode(['books' => $books], JSON_UNESCAPED_UNICODE);
        break;

    case 'chapters':
        $bookName = $_GET['book'] ?? '';
        if (!$bookName) {
            http_response_code(400);
            echo json_encode(['error' => 'Missing book parameter'], JSON_UNESCAPED_UNICODE);
            exit;
        }
        $bookDir = "$bookRoot/$bookName";
        if (!is_dir($bookDir)) {
            http_response_code(404);
            echo json_encode(['error' => 'Book not found'], JSON_UNESCAPED_UNICODE);
            exit;
        }
        $audioExts = ['mp3', 'm4a', 'ogg', 'wav', 'aac', 'flac'];
        $chapters = [];
        $items = scandir($bookDir);
        foreach ($items as $item) {
            if ($item[0] === '.') continue;
            $ext = strtolower(pathinfo($item, PATHINFO_EXTENSION));
            if (in_array($ext, $audioExts)) {
                // 提取文件名（无扩展名）
                $name = pathinfo($item, PATHINFO_FILENAME);
                // 提取数字用于排序
                preg_match('/\d+/', $name, $matches);
                $sortKey = $matches ? (int)$matches[0] : 999999;
                $chapters[] = [
                    'file' => "$bookName/$item",
                    'name' => $name,
                    'sortKey' => $sortKey,
                ];
            }
        }
        // 按提取的数字排序
        usort($chapters, fn($a, $b) => $a['sortKey'] - $b['sortKey']);
        echo json_encode(['chapters' => $chapters], JSON_UNESCAPED_UNICODE);
        break;

    default:
        http_response_code(400);
        echo json_encode(['error' => 'Unknown action'], JSON_UNESCAPED_UNICODE);
        break;
}

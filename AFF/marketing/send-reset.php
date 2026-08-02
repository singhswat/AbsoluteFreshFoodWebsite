<?php
// ── Absolute Fresh — Password Reset Mailer ───────────────────
// Place this file in: public_html/marketing/send-reset.php

header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true);

$to_email   = filter_var($input['email']      ?? '', FILTER_VALIDATE_EMAIL);
$name       = htmlspecialchars(strip_tags($input['name']       ?? 'Partner'));
$reset_link = $input['reset_link'] ?? '';

if (!$to_email || !$reset_link) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid input']);
    exit;
}

$from_email = 'forgotpassword@absolutefreshfood.com';
$from_name  = 'Absolute Fresh';
$subject    = 'Reset your Absolute Fresh password';

$first_name = explode(' ', $name)[0];

$message = "Hi $first_name,\r\n\r\n"
         . "We received a request to reset your Absolute Fresh Partner password.\r\n\r\n"
         . "Click the link below to set a new password:\r\n"
         . "$reset_link\r\n\r\n"
         . "This link expires in 1 hour.\r\n\r\n"
         . "If you didn't request this, you can safely ignore this email — your password won't change.\r\n\r\n"
         . "— Team Absolute Fresh";

$headers  = "From: $from_name <$from_email>\r\n";
$headers .= "Reply-To: $from_email\r\n";
$headers .= "MIME-Version: 1.0\r\n";
$headers .= "Content-Type: text/plain; charset=UTF-8\r\n";
$headers .= "X-Mailer: PHP/" . phpversion();

$sent = mail($to_email, $subject, $message, $headers);

if ($sent) {
    echo json_encode(['success' => true]);
} else {
    http_response_code(500);
    echo json_encode(['error' => 'Mail sending failed']);
}

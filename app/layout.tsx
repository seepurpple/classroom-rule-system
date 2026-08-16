import type { Metadata } from "next";
import "./globals.css";

const title = "모두의 역할 | 1학년 3반";
const description = "학급 역할과 포인트를 한 곳에서 관리하는 교실 운영 도구";
export const metadata: Metadata = { title, description, icons: { icon: "/favicon.svg", shortcut: "/favicon.svg" }, openGraph: { title, description, images: [{ url: "/og.png", width: 1200, height: 630 }] }, twitter: { card: "summary_large_image", title, description, images: ["/og.png"] } };

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  );
}

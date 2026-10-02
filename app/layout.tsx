import type { Metadata } from "next";
import "./globals.css";

const title = "PetClass | 우리 반 성장 이야기";
const description = "우리 반 포인트로 함께 키우는 열두 친구, 서른여섯 가지 성장 이야기";
export const metadata: Metadata = { title, description, icons: { icon: "/favicon.svg", shortcut: "/favicon.svg" }, openGraph: { title, description, images: [{ url: "/assets/pets/seedfox-3.webp", width: 640, height: 640 }] }, twitter: { card: "summary_large_image", title, description, images: ["/assets/pets/seedfox-3.webp"] } };

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

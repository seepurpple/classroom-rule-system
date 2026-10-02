"use client";
import { useEffect } from "react";

// 학급 운영 화면은 PetClass 메뉴로 합쳐졌다. 예전 링크는 홈으로 보낸다.
export default function Classroom() {
  useEffect(() => { window.location.replace("/"); }, []);
  return null;
}

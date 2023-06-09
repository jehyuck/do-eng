import React from "react"
import { NavLink } from "react-router-dom"

/*
마이페이지(/mypage) 내부에서 페이지를 이동할 수 있는 탭(네비게이션)
*/

export default function MyPageTab() {
  // NavLink 기본 tailwind Class
  const defaultClass =
    "flex-1 flex justify-center items-center px-3 py-0.5 bg-opacity-[0.78] text-[32px] whitespace-nowrap duration-[0.22s] "
  // NavLink 활성 시 tailwind Class
  const activeClass = "bg-orange-500 text-white font-hopang-black"
  // NavLink 비활성 시 tailwind Class
  const inactiveClass =
    "border-orange-400 border-b-2 bg-white bg-opacity-80 text-orange-500 font-hopang-white "

  return (
    <div className={`flex flex-nowrap sticky left-0 top-0 w-full`}>
      <NavLink
        to="/mypage/progress"
        className={({ isActive }) =>
          defaultClass + (isActive ? activeClass : inactiveClass)
        }
      >
        학습 진행도
      </NavLink>
      <NavLink
        to="/mypage/talestore"
        className={({ isActive }) =>
          defaultClass + (isActive ? activeClass : inactiveClass)
        }
      >
        책 구매
      </NavLink>
      <NavLink
        to="/mypage/profile"
        className={({ isActive }) =>
          defaultClass + (isActive ? activeClass : inactiveClass)
        }
      >
        회원 정보
      </NavLink>
    </div>
  )
}

import axios, { AxiosRequestConfig } from "axios"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import apiRequest from "utils/axios"
import { queryKeys } from "./queryKeys"

export interface ID {
  id: number
}

export interface Word extends ID {
  image: string
  engWord: string
  korWord: string
  voice: string
}

// 유저 정보
export interface User extends ID {
  memberId: string
  email: string
  nickname: string
  name: string
  phone: string
  createdAt: string
}

// play 부분
export interface PlayTale extends ID {
  title: string
  backgroundImage: string
  score: number
  purchased: boolean
}

export interface PlayWord extends ID, Word {
  correct: boolean
}
export interface PlayTaleDetail extends ID {
  title: string
  sceneOrder: number
  sceneCount: number
  mainImage: string
  taleDone: boolean
  wordList: PlayWord[]
}
export interface Script {
  scriptOrder: number
  content: string
  voice: string
}
export interface Scene extends ID {
  image: string
  sceneOrder: string
  interactiveType: number
  backgroundMusic: string
  scriptList: Script[]
  word: Word
}
export interface TestWord extends Word {
  wrongImage: string
  korVoice: string
}
export interface WordTest {
  title: string
  testList: TestWord[]
}

export interface TestResult {
  id: number
  image: string
  engWord: string
  korWord: string
}

export interface WordResult {
  title: string
  testList: TestResult[]
}

export interface ProgressTale extends ID {
  title: string
  backgroundImage: string
  progress: number
}

export interface ProgressImage extends ID {
  image: string
}
export interface ProgressScene extends ID {
  sceneTitle: string
  imageList: ProgressImage[]
}
export interface ProgressTestResult {
  testCount: number
  wordList: {
    engWord: string
    correctList: boolean[]
  }[]
}
export interface WordList {
  engWord: string
  correctList: boolean[]
}
export interface ProgressTaleDetail extends ID {
  title: string
  backgroundImage: string
  sceneList: ProgressScene[]
  testResult: ProgressTestResult
}
export interface Material extends ID {
  name: string
}
export interface Review extends ID {
  nickname: string
  score: number
  content: string
}
export interface StoreTale extends PlayTale {}
export interface StoreTaleDetail extends PlayTale {
  description: string
  price: number
  materialList: Material[]
  myReview: Review
  reviewList: Review[]
}

export interface ReviewAPIForm {
  myReview: Review
  reviewList: Review[]
}

export const useUserData = function () {
  return useQuery<User>({
    queryKey: queryKeys.user(),
    queryFn: async function () {
      return apiRequest({
        method: `get`,
        url: `/api/member`,
      }).then((res) => res.data)
    },
  })
}

export const useProgressTaleList = function () {
  return useQuery<ProgressTale[]>({
    queryKey: queryKeys.progressList(),
    queryFn: async function () {
      return apiRequest({
        method: `get`,
        url: `/api/mypage/progress`,
      }).then((res) => res.data[`taleList`])
    },
  })
}

export const useProgressTaleDetail = function (taleId: number) {
  return useQuery<ProgressTaleDetail>({
    queryKey: queryKeys.progressDetail(taleId),
    queryFn: async function () {
      return apiRequest({
        method: `get`,
        url: `/api/mypage/progress/${taleId}`,
      }).then((res) => res.data)
    },
  })
}

export const useStoreTaleList = function () {
  return useQuery<StoreTale[]>({
    queryKey: queryKeys.storeList(),
    queryFn: async function () {
      return apiRequest({
        method: `get`,
        url: `/api/mypage/tale-list`,
      }).then((res) => res.data[`taleList`])
    },
  })
}

export const useStoreTaleDetail = function (taleId: number) {
  return useQuery<StoreTaleDetail>({
    queryKey: queryKeys.storeDetail(taleId),
    queryFn: async function () {
      return apiRequest({
        method: `get`,
        url: `/api/mypage/tale-list/${taleId}`,
      }).then((res) => res.data)
    },
  })
}

export const useReviewList = function (taleId: number) {
  return useQuery<ReviewAPIForm>({
    queryKey: queryKeys.reviewList(taleId),
    queryFn: async function () {
      return apiRequest({
        method: `get`,
        url: `/api/mypage/review/${taleId}/review-list`,
      }).then((res) => res.data)
    },
  })
}

export const usePlayTaleList = function () {
  return useQuery<PlayTale[]>({
    queryKey: queryKeys.playList(),
    queryFn: async function () {
      return apiRequest({
        method: `get`,
        url: `/api/tale/list`,
      }).then((res) => res.data)
    },
  })
}

export const usePlayTaleDetail = function (taleId: number) {
  return useQuery<PlayTaleDetail>({
    queryKey: queryKeys.playDetail(taleId),
    queryFn: async function () {
      return apiRequest({
        method: `get`,
        url: `/api/tale/${taleId}/detail`,
      }).then((res) => res.data)
    },
  })
}

export const useWordList = function () {
  return useQuery<PlayWord[]>({
    queryKey: queryKeys.word(),
    queryFn: async function () {
      return apiRequest({
        method: `get`,
        url: `/api/word`,
      }).then((res) => res.data[`wordList`])
    },
  })
}

export const useSceneList = function (taleId: number) {
  return useQuery<Scene[]>({
    queryKey: queryKeys.sceneList(taleId),
    queryFn: async function () {
      return apiRequest({
        method: `get`,
        url: `/api/game/${taleId}/scene`,
      }).then((res) => res.data[`sceneList`])
    },
  })
}

export const useSceneDetail = function (taleId: number, sceneOrder: number) {
  return useQuery<Scene>({
    queryKey: queryKeys.sceneDetail(taleId, sceneOrder),
    queryFn: async function () {
      return apiRequest({
        method: `get`,
        url: `/api/game/${taleId}/scene/${sceneOrder}`,
      }).then((res) => res.data)
    },
    refetchOnWindowFocus: false,
    refetchOnMount: false,
  })
}

export const useWordTestResult = function (taleId: number) {
  return useQuery<WordTest>({
    queryKey: queryKeys.wordList(),
    queryFn: async function () {
      return apiRequest({
        method: `get`,
        url: `/api/word-test/${taleId}`,
      }).then((res) => res.data)
    },
  })
}

// export const useUserMutation = function () {
//   const queryClient = useQueryClient()
//   return useMutation(
//     function (request: AxiosRequestConfig) {
//       return apiRequest(request)
//     },
//     {
//       onSuccess() {
//         queryClient.invalidateQueries(queryKeys.user())
//       },
//     },
//   )
// }

export const useUserMutation = function () {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: function (request: AxiosRequestConfig) {
      return apiRequest(request)
    },
    onSuccess: function () {
      queryClient.invalidateQueries(queryKeys.user())
    },
  })
}

export const useTestMutation = function () {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: function (request: AxiosRequestConfig) {
      return apiRequest(request)
    },
    onSuccess: function () {
      queryClient.invalidateQueries(queryKeys.game())
    },
  })
}

export const useProgressDetailMutation = function (taleId: number) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: function (request: AxiosRequestConfig) {
      return apiRequest(request)
    },
    onSuccess: function () {
      queryClient.invalidateQueries(queryKeys.progressDetail(taleId))
    },
  })
}

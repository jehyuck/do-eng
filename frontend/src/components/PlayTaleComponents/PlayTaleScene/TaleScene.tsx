import {
  useSceneList,
  useSceneDetail,
  usePlayTaleDetail,
} from "hooks/queries/queries"
import React, {
  useState,
  useRef,
  useEffect,
  PropsWithChildren,
  useMemo,
  useCallback,
} from "react"
import { queryKeys } from "hooks/queries/queryKeys"
import { useNavigate, useParams } from "react-router-dom"
import AnimationBox, {
  textOneByOne,
  textOneByOnePpyong,
} from "components/UI/AnimationBox"
import LoadingPage from "pages/LoadingPage"

interface TaleSceneProps {
  taleId: number
  sceneOrder: number
  changeScene: () => void
  isKor?: boolean
  isPause?: boolean
}

function TaleScene({
  taleId,
  sceneOrder,
  changeScene,
  isKor = false,
  isPause = false,
}: PropsWithChildren<TaleSceneProps>) {
  const { data } = usePlayTaleDetail(taleId)
  const maxlength = data?.sceneCount
  const navigate = useNavigate()

  const {
    isLoading: sceneDetailLoading,
    error: sceneDetailError,
    data: sceneDetail,
  } = useSceneDetail(1, sceneOrder)

  const [backgroundMusicAudio, setBackgroundMusicAudio] =
    useState<HTMLAudioElement | null>(null)
  const [scriptListAudio, setScriptListAudio] =
    useState<HTMLAudioElement | null>(null)
  const backgroundMusicAudioRef = useRef<HTMLAudioElement>(null)
  const scriptListAudioRef = useRef<HTMLAudioElement>(null)

  const playEngScript = useCallback(
    function () {
      if (scriptListAudioRef.current) {
        const audioElement = scriptListAudioRef.current
        audioElement.src = sceneDetail?.scriptList[0]?.voice || ""
        audioElement.play()
        setScriptListAudio(audioElement)
      }
    },
    [sceneDetail?.scriptList[0]?.voice, scriptListAudioRef.current],
  )
  const playKorScript = useCallback(
    function () {
      if (scriptListAudioRef.current) {
        const audioElement = scriptListAudioRef.current
        audioElement.src = sceneDetail?.scriptList[1]?.voice || ""
        audioElement.play()
        setScriptListAudio(audioElement)
      }
    },
    [sceneDetail?.scriptList[1]?.voice, scriptListAudioRef.current],
  )
  const runBackgroundMusic = useCallback(
    function () {
      if (backgroundMusicAudioRef.current) {
        const audioElement = backgroundMusicAudioRef.current
        audioElement.src = sceneDetail?.backgroundMusic || ""
        audioElement.loop = true
        audioElement.play()
        setBackgroundMusicAudio(audioElement)
      }
    },
    [sceneDetail?.backgroundMusic],
  )

  const engScripts = useMemo(
    function () {
      let engLi: string[] = []
      if (sceneDetail?.scriptList[0].content) {
        // for (let v of sceneDetail?.scriptList[0].content) {
        //   engLi.push(v)
        // }
        engLi = sceneDetail.scriptList[0].content.split(" ")
      }
      return engLi
    },
    [sceneDetail?.scriptList[0].content, sceneDetailLoading],
  )

  const korScripts = useMemo(
    function () {
      let korLi: string[] = []
      if (sceneDetail?.scriptList[1].content) {
        // for (let v of sceneDetail?.scriptList[0].content) {
        //   korLi.push(v)
        // }
        korLi = sceneDetail.scriptList[1].content.split(" ")
      }
      return korLi
    },
    [sceneDetail?.scriptList[0].content, sceneDetailLoading],
  )

  useEffect(
    function () {
      if (sceneOrder < maxlength!) {
        return
      }
      navigate(`/playtale/${taleId}/test`)
    },
    [sceneOrder, maxlength],
  )

  useEffect(() => {
    runBackgroundMusic()
    // playEngScript()
  }, [runBackgroundMusic, sceneDetailLoading])

  useEffect(
    function () {
      if (isKor) {
        scriptListAudioRef.current?.pause()
        const a = setTimeout(playKorScript, 100)
        return function () {
          clearTimeout(a)
        }
      } else {
        scriptListAudioRef.current?.pause()
        const a = setTimeout(playEngScript, 100)
        return function () {
          clearTimeout(a)
        }
      }
    },
    [sceneOrder, sceneDetailLoading, isKor],
  )

  useEffect(
    function () {
      if (isPause) {
        scriptListAudioRef.current?.play()
      } else {
        scriptListAudioRef.current?.pause()
      }
    },
    [isPause, scriptListAudioRef.current],
  )

  // useEffect(() => {
  //   if (scriptListAudio) {
  //     scriptListAudio.addEventListener("ended", () => {
  //       if (maxlength && sceneOrder < maxlength) {
  //         // changeScene()
  //         const timeoutId = setTimeout(changeScene, 3000)
  //         return function () {
  //           clearTimeout(timeoutId)
  //         }
  //       }
  //     })
  //   }
  // }, [scriptListAudio, sceneDetail, sceneOrder, sceneDetailLoading])

  //   const plusScene = function () {
  //     if (maxlength && sceneOrder < maxlength) {
  //       setSceneOrder((val) => val + 1)
  //     }
  //     console.log(sceneDetail, "123")
  //   }

  if (sceneDetailLoading) {
    return <LoadingPage />
  }
  return (
    <>
      <audio ref={backgroundMusicAudioRef} />
      <audio ref={scriptListAudioRef} />
      <div className="h-full w-full bg-scene-back content-center bg-no-repeat bg-cover relative">
        <img
          src={sceneDetail?.image}
          className="h-[88%] w-full bg-img-gradient object-contain top-[50%] left-[50%] absolute translate-x-[-50%] translate-y-[-55%] z-[40]"
        />
        <div className="relative z-[49] left-[50%] bottom-[-70%] w-[70%] h-auto p-5 flex flex-row flex-wrap items-center justify-center translate-x-[-50%] font-jalnan text-[26px] gap-[0.5rem]">
          {engScripts.map((val, idx) => {
            return (
              <>
                <AnimationBox
                  key={`stript-eng-${idx}`}
                  boxClasses="drop-shadow-xl"
                  appearClassName={`${textOneByOne[idx + 5]}`}
                >
                  {val}
                </AnimationBox>
              </>
            )
          })}
        </div>
        <div className="relative z-[49] left-[50%] bottom-[-70%] w-[70%] h-auto p-5 flex flex-row flex-wrap items-center justify-center translate-x-[-50%] font-jalnan text-[26px] gap-[0.5rem]">
          {isKor
            ? korScripts.map((val, idx) => {
                return (
                  <>
                    <AnimationBox
                      key={`stript-eng-${idx}`}
                      boxClasses="drop-shadow-xl"
                      appearClassName={`${textOneByOne[idx + 5]}`}
                    >
                      {val}
                    </AnimationBox>
                  </>
                )
              })
            : null}
        </div>
      </div>
      <div
        onClick={changeScene}
        className="absolute z-[49] left-0 bottom-[50%] p-5 drop-shadow-xl"
      >
        {sceneDetail?.scriptList[0].content}
      </div>
    </>
  )
}

export default TaleScene

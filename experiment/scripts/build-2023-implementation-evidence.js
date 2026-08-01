/*
 * Extracts only Git objects from the selected 2023 DoEng commit.
 * It does not read current source files as evidence and does not run an experiment.
 */
const fs = require('fs')
const path = require('path')
const crypto = require('crypto')
const { execFileSync } = require('child_process')

const root = path.resolve(__dirname, '..', '..')
const git = 'C:\\Users\\KOSCOM\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\native\\git\\cmd\\git.exe'
const commit = '8e856468b36dcb1d7297afc05461af01d6dd6424'
const packageName = 'DoEng-2023-Original-Implementation-Evidence-20260731'
const output = path.join(root, 'evidence-2023', packageName)

if (fs.existsSync(output)) throw new Error(`Refusing to overwrite ${output}`)

function runGit(args, encoding = 'buffer') {
  return execFileSync(git, ['-c', 'safe.directory=*', '-C', root, ...args], { encoding })
}
function textGit(args) { return runGit(args, 'utf8') }
function sha256(content) { return crypto.createHash('sha256').update(content).digest('hex') }
function write(relative, content) {
  const destination = path.join(output, relative)
  fs.mkdirSync(path.dirname(destination), { recursive: true })
  fs.writeFileSync(destination, content)
}
function sourceObject(file) {
  return runGit(['show', `${commit}:${file}`])
}
function pathHistory(file) {
  return textGit(['log', '--format=%H|%aI|%an|%ae|%s', '-8', commit, '--', file]).trim()
}

const sourceFiles = [
  { file: 'backend/doEngGameFlux/build.gradle', relevance: 'Spring WebFlux, R2DBC, MariaDB R2DBC, AWS async SDK dependencies' },
  { file: 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/DoEngGameFluxApplication.java', relevance: 'WebFlux module application entry point' },
  { file: 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/config/WebConfig.java', relevance: 'WebFluxConfigurer implementation' },
  { file: 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/contoller/AiGameController.java', relevance: 'Representative /game/face HTTP request and AI WebClient chain' },
  { file: 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/component/TokenComponent.java', relevance: 'Reactive WebClient token-validation request' },
  { file: 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/component/DBComponentHttp.java', relevance: 'Representative HTTP success-path storage and DB side effects' },
  { file: 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/component/CustomFilePart.java', relevance: 'Byte array to reactive FilePart bridge used for storage upload' },
  { file: 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/repository/ProgressRepository.java', relevance: 'ReactiveCrudRepository and reactive progress query/update' },
  { file: 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/repository/PictureRepository.java', relevance: 'ReactiveCrudRepository for picture record' },
  { file: 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/entity/Progress.java', relevance: 'Spring Data relational mapping used by progress repository' },
  { file: 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/entity/Picture.java', relevance: 'Spring Data relational mapping used by picture repository' },
  { file: 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/s3/S3Config.java', relevance: 'S3AsyncClient with Netty async HTTP client configuration' },
  { file: 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/s3/PictureUtil.java', relevance: 'S3AsyncClient multipart upload and Mono.fromFuture composition' },
  { file: 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/s3/AwsS3Service.java', relevance: 'Storage-path collaborator invoked before upload' },
]

const commitInfo = textGit(['show', '-s', '--format=commit=%H%nauthor=%an <%ae>%nauthorDate=%aI%ncommitter=%cn <%ce>%ncommitterDate=%cI%nparents=%P%nsubject=%s%n%n%B', commit])
const topLevel = textGit(['ls-tree', '--name-only', commit])
write('git/commit.txt', [
  'Selection: master@8e85646 resolves to the full SHA below and is the final master tip recorded on 2023-04-07.',
  'Reason for selection: it is the repository master/origin-master tip, falls within the recorded project period, and its tree contains the DoEng Game Flux module. The commit itself changes only a frontend file, so it is used as a project snapshot, not as proof that all Flux files were authored in this merge.',
  'Scope warning: current working-tree files are not evidence in this package; all source files under source/ were read with git show <full-sha>:<path>.',
  '', commitInfo, '', 'top-level tree:', topLevel,
].join('\n'))

const histories = sourceFiles.map(({ file }) => `## ${file}\n${pathHistory(file) || 'NO PATH HISTORY FOUND'}\n`).join('\n')
write('git/log.txt', [
  '# Recent first-parent master history',
  textGit(['log', '--first-parent', '--format=%H|%aI|%an|%ae|%s', '-12', commit]).trim(),
  '', '# Relevant path histories (latest first, ending at selected commit)', histories,
].join('\n'))
const rationaleLog = textGit(['log', '--all', '--format=%H|%aI|%an|%s', '--regexp-ignore-case', '--grep=webflux|reactive|r2dbc|non.?blocking|비동기|논블로킹']).trim()
write('git/rationale-search.txt', [
  'Search scope: all commit subjects in this local repository, case-insensitive, for WebFlux/reactive/R2DBC/non-blocking and Korean equivalents.',
  'Command: git log --all --regexp-ignore-case --grep=webflux|reactive|r2dbc|non.?blocking|비동기|논블로킹',
  '', rationaleLog || 'NO MATCH',
].join('\n'))
write('git/blame-selected-lines.txt', [
  '# AiGameController requestFaceAi lines 55-90',
  textGit(['blame', '-L', '55,90', commit, '--', 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/contoller/AiGameController.java']),
  '# DBComponentHttp lines 26-63',
  textGit(['blame', '-L', '26,63', commit, '--', 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/component/DBComponentHttp.java']),
  '# PictureUtil lines 20-140',
  textGit(['blame', '-L', '20,140', commit, '--', 'backend/doEngGameFlux/src/main/java/com/example/doenggameflux/s3/PictureUtil.java']),
].join('\n'))

const manifestItems = []
for (const item of sourceFiles) {
  const content = sourceObject(item.file)
  const destination = path.join('source', item.file).replaceAll('\\', '/')
  write(destination, content)
  const history = pathHistory(item.file).split('\n')[0].split('|')
  manifestItems.push({
    originalPath: item.file,
    packagedPath: destination,
    sourceCommit: commit,
    sourceCommitDate: '2023-04-07T11:20:36+09:00',
    objectSha256: sha256(content),
    bytes: content.length,
    lastPathCommit: history[0] || 'UNKNOWN',
    lastPathCommitDate: history[1] || 'UNKNOWN',
    lastPathAuthor: history[2] ? `${history[2]} <${history[3]}>` : 'UNKNOWN',
    relevance: item.relevance,
  })
}

const pathMap = `# 대표 요청 경로: POST /game/face

선택 기준: 선택 commit의 HTTP controller에서 이미지, AI 호출, storage, DB가 모두 만나는 대표 경로다.

Request:
- POST /game/face?answer=...&sceneId=...

## 1. Controller

- file: source/backend/doEngGameFlux/src/main/java/com/example/doenggameflux/contoller/AiGameController.java
- method: requestFaceAi(@RequestBody Mono<ImageRequestDto> image, ...)
- return type: Mono<ResponseEntity<String>>
- evidence: @PostMapping("/game/face"), image.map(...).flatMap(...).onErrorResume(...)
- reactive/blocking 판정: reactive controller. 다만 성공 결과의 Base64.getDecoder().decode(...)는 동기 CPU 작업이다.

## 2. AI I/O

- file: source/backend/doEngGameFlux/src/main/java/com/example/doenggameflux/contoller/AiGameController.java
- method: makeWebClient(Map<String, String>, String)
- client: org.springframework.web.reactive.function.client.WebClient
- evidence: WebClient.builder().post().uri(url).bodyValue(map).retrieve().bodyToMono(FaceResultResponseDto.class)
- reactive/blocking 판정: reactive HTTP API. /game/face는 flatMap으로 이 Mono를 연결한다. 명시적 timeout은 이 메서드에 없다; WebClientResponseException만 controller에서 onErrorResume한다.

참고 토큰 I/O:
- file: source/backend/doEngGameFlux/src/main/java/com/example/doenggameflux/component/TokenComponent.java
- method: jwtConfirm / makeWebClient
- evidence: WebClient GET과 bodyToMono(TokenResponseDto.class)를 Mono chain으로 연결한다.

## 3. Storage I/O

- file: source/backend/doEngGameFlux/src/main/java/com/example/doenggameflux/component/DBComponentHttp.java
- method: saveData
- client: PictureUtil -> S3AsyncClient
- evidence: getUser().flatMap(...uploadUserProfilePict...).subscribeOn(Schedulers.boundedElastic()).subscribe()
- reactive/blocking 판정: PictureUtil 내부의 storage client와 Future-to-Mono 변환은 async/reactive API다. 그러나 이 HTTP 경로에서는 subscribe()로 독립 실행해 반환 Mono에 연결하지 않았으므로, 응답은 S3 완료를 기다리지 않는다.

Storage 구현 근거:
- file: source/backend/doEngGameFlux/src/main/java/com/example/doenggameflux/s3/S3Config.java
- evidence: S3AsyncClient + NettyNioAsyncHttpClient
- file: source/backend/doEngGameFlux/src/main/java/com/example/doenggameflux/s3/PictureUtil.java
- evidence: s3AsyncClient.createMultipartUpload/uploadPart/completeMultipartUpload 및 Mono.fromFuture(...)

## 4. DB I/O

- file: source/backend/doEngGameFlux/src/main/java/com/example/doenggameflux/component/DBComponentHttp.java
- method: saveDataBase
- access technology: Spring Data R2DBC / ReactiveCrudRepository
- evidence: ProgressRepository.getByMemberIdAndSceneId(...), switchIfEmpty(progressRepository.save(...))
- reactive/blocking 판정: repository interface와 반환 타입은 reactive다. 다만 pictureRepository.save(...).subscribe()와 progressRepository.updateProgress(...).subscribe()는 반환 Mono에서 분리되어, 해당 write 완료가 HTTP 응답 성공 조건으로 합성되지 않는다.

## 5. Response composition

- file: source/backend/doEngGameFlux/src/main/java/com/example/doenggameflux/contoller/AiGameController.java
- method: requestFaceAi
- evidence: dbComponent.saveData(...).then(Mono.just(ResponseEntity.ok().body("true")))
- 판정: dbComponent가 반환한 Mono 이후 응답을 구성한다. 그러나 DBComponentHttp 내부에서 S3와 일부 DB write를 별도 subscribe()로 시작하므로, 전체 외부 I/O 완료를 하나의 chain으로 기다리는 구조는 아니다.

## 전체 판정

- **mixed**
- 근거: controller, AI WebClient, R2DBC repository, S3AsyncClient는 reactive/async API를 실제 사용한다. 반면 요청 성공 경로에 동기 Base64 decode가 있고, S3 upload 및 일부 DB write가 detached subscribe()로 실행되어 end-to-end completion chain이 완결되지 않는다.
`
write('analysis/request-path-map.md', pathMap)

const facts = `# 2023 구현 사실 판정

## 판정표

| 항목 | 판정 | 원본 근거 |
|---|---|---|
| WebFlux dependency | CONFIRMED | build.gradle의 spring-boot-starter-webflux |
| Reactive Controller/Service | PARTIAL | AiGameController의 Mono 반환과 flatMap; DBComponentHttp 내부 detached subscribe() |
| WebClient | CONFIRMED | AiGameController 및 TokenComponent의 WebClient + bodyToMono |
| R2DBC | CONFIRMED | build.gradle의 data-r2dbc/r2dbc-mariadb, ReactiveCrudRepository |
| Async Storage | CONFIRMED | S3AsyncClient, NettyNioAsyncHttpClient, Mono.fromFuture |
| End-to-End non-blocking path | PARTIAL | API는 reactive지만 Base64 동기 decode와 detached subscribe() 경계 존재 |
| 2023 기술 선택 이유가 당시 자료에 존재 | NOT FOUND | git/rationale-search.txt의 commit-subject 검색에서 일치 항목 없음. 선택 이유를 추론하지 않음. |
| 사용자 개인 기여 | PARTIAL | 핵심 경로 파일 history에는 jehyuck 커밋이 다수 존재하나, controller 초기 이력에는 다른 작성자도 있고 팀 repository만으로 개인 단독 구현을 확정할 수 없음. |

## 구현 사실과 후속 해석의 분리

- IMPLEMENTATION FACT: 선택 commit의 Git object에는 WebFlux, WebClient, R2DBC reactive repository, S3AsyncClient 및 Reactor Mono 기반 코드가 존재한다.
- IMPLEMENTATION FACT: 대표 HTTP 경로에는 직접 subscribe()와 동기 Base64 decode가 존재한다.
- LATER INTERPRETATION: 왜 당시 이 구조를 선택했는지, 당시 병목을 측정했는지, MVC와 성능 비교했는지는 이 Git 증거만으로는 말할 수 없다.
`
write('analysis/implementation-facts.md', facts)

const manifest = [
  '# DoEng 2023 원본 구현 Evidence Manifest', '',
  `- Experience ID: DOE-01`,
  `- Selected source commit: ${commit}`,
  '- Selected commit date: 2023-04-07T11:20:36+09:00',
  '- Extraction method: `git show <selected-commit>:<path>` only. No current branch source file is used as 2023 evidence.',
  '- Package creation date: 2026-07-31', '',
  '## 추출 원본 파일', '',
  '| original path | packaged path | source commit | source commit date | SHA-256 | bytes | latest relevant path commit | latest path author | DOE-01 관련성 |',
  '|---|---|---|---|---|---:|---|---|---|',
  ...manifestItems.map((item) => `| ${item.originalPath} | ${item.packagedPath} | ${item.sourceCommit} | ${item.sourceCommitDate} | ${item.objectSha256} | ${item.bytes} | ${item.lastPathCommit} (${item.lastPathCommitDate}) | ${item.lastPathAuthor} | ${item.relevance} |`),
  '',
  '## 주의', '',
  '- `latest relevant path commit`은 해당 파일의 선택 commit 이전 최신 path history이며, 파일 전체의 단독 저작권이나 사용자 개인 기여를 뜻하지 않는다.',
  '- source/의 모든 파일은 선택 commit Git object에서 직접 추출했다. 현재 작업 트리의 실험용 코드와 구분된다.',
  '- analysis/ 문서는 추출한 원본 코드를 읽어 만든 사후 검수 자료이며, 2023 당시 문서가 아니다.', '',
].join('\n')
write('MANIFEST.md', `${manifest}\n`)

console.log(JSON.stringify({ output, sourceFiles: manifestItems.length, commit }, null, 2))

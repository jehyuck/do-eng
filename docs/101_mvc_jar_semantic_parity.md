# MVC Historical vs Bridge JAR Semantic Parity

## 1. Artifact identities

The audit was static. No application container was started and no performance workload was executed.

| Artifact | Image | Image ID | `/app/app.jar` SHA-256 |
|---|---|---|---|
| Historical MVC | `doeng-capacity-closure-20260731-mvc:latest` | `sha256:81f580e585cde6588c71aca72041faeb09b89b87ffc375d473d41f75a959e05e` | `3e846b8be2f00d63bda6793da7cd2a795c9dda8778ab14f087f0d20da9faed5f` |
| Bridge current-mock MVC | `doeng-bridge1s-mock-current-m001-mvc:latest` | `sha256:b2f50a6be8ab9c2bf3db6b80b5ae94c72e0b9e01988962c00178b3df5faec8d1` | `f5e722fd7ace788bf6873463303ea84367c908b4d7e289421eda80ee807c0bf5` |
| Bridge historical-mock MVC | `doeng-bridge1s-mock-hist-m001-mvc:latest` | `sha256:8a9ef49d8f8920e483fac0b3edb474006ed314529a03e0058d389eb329e03667` | `f5e722fd7ace788bf6873463303ea84367c908b4d7e289421eda80ee807c0bf5` |

The historical extraction matched the preregistered SHA-256. Both bridge extractions matched the bridge evidence SHA-256. The bridge current-mock and historical-mock application JARs are byte-for-byte identical as whole files.

## 2. Git source continuity

- Audit HEAD: `c32935f84349a95d93860cbe66cb84575361270f`
- Historical source comparison base: `7c5c522024ae5491d62f4b0c5d2bed63b87d3002`
- `git diff 7c5c522..c32935f -- backend/doEngGameMvc` had no changes.
- No source, Dockerfile, Gradle, config, or runner files were changed during this audit.

## 3. ZIP entry inventory

The historical and bridge JARs each contained 133 non-directory entries. Entry order was equal.

For every entry, the audit collected path, uncompressed size, compressed size, CRC, ZIP timestamp, and SHA-256 of the uncompressed bytes.

- Entry count: equal, 133 vs 133
- Uncompressed size: equal for all entries
- CRC: equal for all entries
- Compressed size: equal for all entries
- Entry order: equal
- ZIP timestamp: different for 65 entries
- Uncompressed semantic byte differences: none

## 4. Application class comparison

`BOOT-INF/classes/**/*.class`: 20 entries, 0 byte differences.

`APPLICATION_CLASS_ENTRY_PARITY: SAME`

## 5. Application resource comparison

`BOOT-INF/classes` non-class resources: 2 entries, 0 byte differences, including the packaged application configuration resource.

`APPLICATION_RESOURCE_PARITY: SAME`

## 6. Dependency comparison

`BOOT-INF/lib/*.jar`: 40 entries, 0 byte differences in filenames, sizes, CRCs, or uncompressed bytes.

`DEPENDENCY_PARITY: SAME`

## 7. Spring Boot loader comparison

`org/springframework/boot/loader/**`: 68 entries, 0 byte differences.

`BOOT_LOADER_PARITY: SAME`

## 8. Manifest and metadata comparison

The whole JAR SHA-256 differs because the archive metadata differs. The semantic entry content does not differ. The observed archive-level difference was ZIP timestamps on 65 entries; CRCs, compressed sizes, uncompressed sizes, and entry order were equal.

`METADATA_DIFFERENCE: YES`

## 9. Normalized content fingerprint

The normalized fingerprint was calculated from sorted `entry path + SHA-256(uncompressed entry bytes)` pairs, ignoring ZIP timestamps, compression metadata, and archive ordering metadata.

```text
HISTORICAL_NORMALIZED_CONTENT_SHA256:
89799b832f3d132e949ce52625f02cdb249409cd879ee25dbe712f707a7b1112

BRIDGE_NORMALIZED_CONTENT_SHA256:
89799b832f3d132e949ce52625f02cdb249409cd879ee25dbe712f707a7b1112
```

`NORMALIZED_CONTENT_PARITY: PASS`

## 10. Gradle reproducibility settings

The current MVC build definition contains Spring Boot `2.7.9`, Java 11 compatibility, and the normal dependency declarations. The MVC experiment Dockerfile uses `gradle:7.6.1-jdk11` and runs `bootJar -x test`.

No explicit `reproducibleFileOrder` or `preserveFileTimestamps` setting was found in `backend/doEngGameMvc/build.gradle` or `settings.gradle`.

`GRADLE_REPRODUCIBLE_ARCHIVE_CONFIG: NOT_PROVEN`

## 11. Final classification

```text
MVC_JAR_SEMANTIC_CLASSIFICATION: SAME_CONTENT_NON_REPRODUCIBLE_ARCHIVE
MVC_APPLICATION_DIFFERENCE: NOT_SUPPORTED
```

The differing whole-file SHA-256 does not establish a historical-vs-bridge MVC application behavior difference. The application classes, resources, dependencies, Spring Boot loader, and normalized content are identical. The observed difference is archive metadata.

## 12. Remaining candidate causes

This audit does not explain the performance outcome difference between the bridge arms. The experiment-mock runtime image remains the intentionally varied bridge condition. Any causal conclusion about runtime behavior requires the existing run evidence and must not be inferred from the whole-JAR SHA alone.

## Audit constraints

```text
PERFORMANCE_LOAD_EXECUTED: NO
APPLICATION_STARTED: NO
CODE_CHANGED: NO
CONFIG_CHANGED: NO
```

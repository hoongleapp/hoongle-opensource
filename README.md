# 훈글(Hoongle)에 들어간 GPL 부품의 소스 / Source code for GPL components in Hoongle

훈글(맥·아이패드용 HWP 문서 편집기)은 아래 오픈 소스 부품을 고치지 않고 그대로 앱에 넣어 씁니다.
이 부품들은 GNU General Public License 2판(+ Classpath 예외)으로 배포되므로, 그 라이선스 3조에 따라
앱에 들어간 것과 같은 판의 소스를 여기에 둡니다. 파일은 이 저장소의 Releases 에 있습니다.

Hoongle (an HWP document editor for Mac and iPad) ships the open-source components below unmodified.
They are licensed under the GNU General Public License, version 2, with the Classpath Exception.
As required by section 3 of that license, the corresponding source code for the exact versions
used in the app is provided here (see Releases).

| 부품 / Component | 쓰는 곳 / Used in | 판 / Version | 원래 저장소 / Upstream | 라이선스 / License |
|---|---|---|---|---|
| OpenJDK 21 | 맥 / Mac | jdk-21.0.12.1-ga | https://github.com/openjdk/jdk21u | GPLv2 + Classpath Exception |
| GraalVM Community (Gluon build) | 아이패드 / iPad | gluon-23+25.1-dev, commit f3da2b22a86e350e979ed94a96583d5561c9040f | https://github.com/gluonhq/graal | GPLv2 + Classpath Exception |
| Labs OpenJDK 23 (GraalVM 의 JDK) | 아이패드 / iPad | 23+25-jvmci-b01, commit 9a5ad54320eafac785d6a9f1b53a7878cd52db38 | https://github.com/graalvm/labs-openjdk | GPLv2 + Classpath Exception |
| Gluon Mobile static JDK libraries | 아이패드 / iPad | gvm-24-2 | https://github.com/gluonhq/mobile | GPLv2 + Classpath Exception |
| Gluon vmone | 아이패드 / iPad | gvm-24-2.1 | https://github.com/gluonhq/vmone | 앱에 들어간 파일은 머리글이 GPLv2 + Classpath Exception / files linked into the app carry GPLv2 + Classpath Exception headers |

- 맥판의 자바 런타임은 Homebrew openjdk@21 (21.0.12.1, 패치 없음)을 jlink 로 줄인 것입니다.
  The Mac runtime is Homebrew openjdk@21 (21.0.12.1, no patches) reduced with jlink.
- 아이패드판은 vmone 정적 라이브러리에서 머리글 없는 빈 조각 dummy.o 하나를 빼고 링크합니다(소스는 그대로).
  The iPad build removes one header-less stub object (dummy.o) from the vmone static library before linking; no source was changed.
- 각 파일의 SHA-256 은 SHA256SUMS.txt 에 있습니다. / SHA-256 checksums are in SHA256SUMS.txt.

**서면 제안 / Written offer** — 이 저장소를 쓸 수 없게 되더라도, 해당 판을 배포한 날로부터 3년 동안
hoongle.help@gmail.com 으로 요청하시면 같은 소스를 드립니다(전달 비용 외에 돈을 받지 않습니다).
For at least three years from distribution, the same source is available on request at hoongle.help@gmail.com
(no charge beyond the cost of physically delivering it).

훈글은 주식회사 한글과컴퓨터와 관계없는 독립 프로그램입니다.
Hoongle is an independent program and is not affiliated with Hancom Inc.

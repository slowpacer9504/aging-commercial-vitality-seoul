# 고령화가 근린 상업 활력에 미치는 영향: 서울시 빅데이터를 이용한 시공간 분석

본 프로젝트는 고령화가 서울시 행정동 근린 상권의 활력에 미치는 직·간접적인 영향과 시공간적 이질성을 추정하기 위한 분석 코드베이스 및 연구 명세 패키지입니다.

---

## 1. 프로젝트 폴더 구조 (Directory Structure)

본 저장소는 연구 재현성을 극대화하기 위해 다음과 같이 구조화되어 있습니다.

```text
├── 01_Data/                  # 분석용 데이터 (Git 추적 제외)
│   ├── 01_Raw_Data/          # 수집된 원천 공공데이터
│   ├── 02_Boundary/          # 서울시 행정동 경계 공간 데이터
│   └── 03_Processed_Data/    # 전처리 및 결합 완료된 분석 패널 데이터
│
├── 02_Code/                  # 분석 파이프라인 스크립트
│   ├── 00_setup/             # 패키지 설치 및 공용 설정
│   ├── 01_preprocess/        # 분기 패널 데이터 구축 및 변수/활력지수 생성
│   ├── 02_esda/              # 공간가중행렬 구축 및 공간 자기상관 진단 (Moran's I, LISA)
│   ├── 03_models/            # 패널 모형 추정 (TWFE baseline, SPDM main, GTWR local sidecar)
│   ├── 04_robustness/        # 모형 강건성 검정 (공간가중행렬 민감도 등)
│   ├── 05_reporting/         # 결과 테이블 및 시각화 그림 생성
│   ├── 06_qc/                # 데이터 계약 및 모형 정합성 품질 관리 (QC)
│   ├── 80_optional/          # 상호작용 분석, 매개경로 분석 등 부가 분석 스크립트
│   ├── 90_templates/         # 코드 작성용 실행 템플릿
│   ├── 99_utils/             # 공용 유틸리티 헬퍼 함수 (.R)
│   ├── run_all.R             # 전 과정 자동 실행 파이프라인 스크립트
│   └── README.md             # 분석 코드 상세 설명서
│
├── 03_Output/                # 모형 추정 결과물 및 보고용 표·그림 (Git 추적 제외)
│
├── 04_Docs/                  # 연구 명세서 및 가이드라인
│   ├── 01_Design/            # 연구 계획서 및 수행 절차서
│   └── 02_Codebook/          # 데이터 스펙, 변수 사전, 모델 사양 매핑 명세서
│
├── README.md                 # 본 메인 가이드 문서
├── AGENTS.md                 # 에이전트 작업 수행 가이드라인 (Git 추적 제외)
└── R.Rproj                   # RStudio 프로젝트 파일
```

---

## 2. 분석 가이드 및 실행 순서 (Quick Start)

본 분석은 `here` 패키지를 통해 프로젝트 루트 폴더를 자동으로 인식합니다. 재현 시 반드시 `R.Rproj` 파일을 실행한 후 분석을 시작하십시오.

### 2.1 패키지 설치
처음 환경을 설정할 때 아래 스크립트를 실행하여 필요한 R 패키지들을 한 번에 설치합니다.
```R
source("02_Code/00_setup/install_packages.R")
```

### 2.2 파이프라인 전체 실행
분석 전처리부터 모델 추정, 표·그림 출력까지의 전체 기본 파이프라인을 실행하려면 다음 명령어를 실행합니다.
```R
source("02_Code/run_all.R")
```
또는 터미널(Bash) 환경에서 다음과 같이 실행할 수도 있습니다.
```bash
Rscript 02_Code/run_all.R
```

---

## 3. 핵심 연구 명세서 (Documentation Reference)

연구의 상세 이론적 배경, 변수 정의 및 모델 방정식은 다음 문서를 참조하십시오.

* **연구 계획 요약**: [research_plan.md](file:///Users/junghyunpyo/Library/CloudStorage/GoogleDrive-hanuiwind25%40gmail.com/%EB%82%B4%20%EB%93%9C%EB%9D%BC%EC%9D%B4%EB%B8%8C/%EB%AC%B8%EC%84%9C/%EB%85%BC%EB%AC%B8/R/04_Docs/01_Design/research_plan.md)
* **단계별 실행 절차**: [research_procedure.md](file:///Users/junghyunpyo/Library/CloudStorage/GoogleDrive-hanuiwind25%40gmail.com/%EB%82%B4%20%EB%93%9C%EB%9D%BC%EC%9D%B4%EB%B8%8C/%EB%AC%B8%EC%84%9C/%EB%85%BC%EB%AC%B8/R/04_Docs/01_Design/research_procedure.md)
* **변수 및 모형 명세 허브**: [00_spec_index.md](file:///Users/junghyunpyo/Library/CloudStorage/GoogleDrive-hanuiwind25%40gmail.com/%EB%82%B4%20%EB%93%9C%EB%9D%BC%EC%9D%B4%EB%B8%8C/%EB%AC%B8%EC%84%9C/%EB%85%BC%EB%AC%B8/R/04_Docs/02_Codebook/00_spec_index.md)

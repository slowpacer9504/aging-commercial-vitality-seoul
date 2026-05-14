# 연구 스펙 인덱스 (Spec Index)

이 문서는 코딩 시 참조해야 하는 핵심 명세의 허브다. 현재 active contract는 **서울시 행정동 연도 패널(`adm_cd x year`)** 이다.

구현 스크립트는 역할별 폴더 구조와 폴더-local 번호 체계를 따른다. 해석해야 할 canonical dataset/key/timing/output naming은 이 codebook이 선언하는 annual contract를 따른다.

## 기준 설계 문서

- [research_plan.md](../01_Design/research_plan.md)
- [research_procedure.md](../01_Design/research_procedure.md)
- [paper_methods_blueprint.md](../01_Design/paper_methods_blueprint.md)
- [r_code_style_guide.md](../01_Design/r_code_style_guide.md)

## 실행 템플릿

- [00_template_preprocessing_aging_commerce.R](../../02_Code/90_templates/00_template_preprocessing_aging_commerce.R)
- [00_template_modeling_aging_commerce.R](../../02_Code/90_templates/00_template_modeling_aging_commerce.R)

## 명세 문서

1. [01_data_spec.md](./01_data_spec.md)
2. [02_variable_dictionary.md](./02_variable_dictionary.md)
3. [03_join_harmonization_rules.md](./03_join_harmonization_rules.md)
4. [04_model_spec.md](./04_model_spec.md)
5. [99_spec_to_code_map.csv](./99_spec_to_code_map.csv)

## 빠른 참조 순서

1. 데이터 계층, 출력 위치, QC 로그 확인: `01_data_spec.md`
2. 변수 정의와 annualization rule 확인: `02_variable_dictionary.md`
3. 조인 키와 harmonization rule 확인: `03_join_harmonization_rules.md`
4. 모형식, FE, timing, output contract 확인: `04_model_spec.md`
5. 실제 스크립트 매핑 확인: `99_spec_to_code_map.csv`

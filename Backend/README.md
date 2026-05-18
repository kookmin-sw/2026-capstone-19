# KMU Taxi Mate

국민대학교 학생들을 대상으로 하는 택시 동승 매칭 및 정산 서비스입니다.  
사용자는 출발지, 도착지, 출발 시각을 기준으로 동승 모집을 생성하거나 참여할 수 있으며,  
모임장은 외부 택시 호출 앱을 통해 택시를 호출한 뒤 영수증을 업로드하여 1/N 정산을 요청할 수 있습니다.

이 프로젝트는 현재 **Django + PostgreSQL** 기반 백엔드 구조로 개발 중이며,  
DB 스키마는 **Django models + Django migrations**를 기준으로 관리합니다.

---

## 프로젝트 목표

- 교통 접근성이 상대적으로 불편한 국민대학교 학생들을 위한 택시 동승 서비스 제공
- 출발지/도착지/출발 시각 기반의 직관적인 모집 기능 제공
- 외부 송금 링크(카카오페이)를 활용한 간편 정산 기능 제공
- 영수증 기반의 투명한 1/N 정산 구조 구현
- 채팅, 평가, 신고, 패널티 기능을 통한 신뢰 기반 커뮤니티 형성

---

## 주요 기능

### 1. 사용자 관리
- 국민대학교 웹메일 기반 사용자 인증
- 닉네임 및 프로필 이미지 관리
- 평판 점수(trust_score) 관리
- 패널티 및 이용 제한 관리

### 2. 동승 모집
- 출발지 / 도착지 / 출발 시각 입력
- 예상 택시 요금 표시
- 모집 인원 제한
- 모집 상태 관리
  - OPEN
  - FULL
  - CANCELED
  - CLOSED
  - COMPLETED

### 3. 정산 기능
- 모임장(대표 사용자)의 카카오페이 송금 링크 등록
- 영수증 업로드
- 총 결제 금액(total_amount) 기준 1/N 정산
- 정산 상태 관리
  - REQUESTED
  - PAID_SELF
  - CONFIRMED
  - DISPUTED
  - OVERDUE
  - CANCELED
- 송금 캡처 등 증빙 업로드

### 4. 채팅 기능
- 모집별 채팅방 1개 생성
- 참여자 간 메시지 송수신

### 5. 운영/관리 기능
- 상호 평가(리뷰)
- 신고 기능
- 패널티 기록 및 이용 제한
- Django Admin을 활용한 운영 관리

---

## 기술 스택

### Backend
- Django
- Django REST Framework

### Database
- PostgreSQL

### Environment
- Python 3.x
- virtualenv (venv)

### Admin / Management
- Django Admin

---

## 현재 백엔드 구조

이 프로젝트의 백엔드는 **Django + PostgreSQL** 기반으로 구성되어 있습니다.

- Django가 백엔드 로직, 모델, 관리자 페이지를 담당
- PostgreSQL이 실제 데이터 저장을 담당
- DB 구조 변경은 **Django migrations**로 관리

> 주의:  
> 기존 Prisma 기반 설정은 더 이상 사용하지 않습니다.  
> 현재 DB 마이그레이션 기준은 **Django**입니다.

---

## 프로젝트 구조

```text
Backend/
  accounts/
  trips/
  settlements/
  chat/
  moderation/
  config/
  manage.py
  requirements.txt
  .env.example


## 로컬 실행방법
1. 프로젝트 폴더로 이동
    - cd Backend 
2. 가상환경 생성
    - python -m venv venv
3. 가상환경 활성화(윈도우 기준)
    - .\venv\Scripts\Activate.ps1
4. 패키지 설치
    - pip install -r requirements.txt
5. .env 파일 생성(.env.example 참고)


## Django 마이그레이션
1. 마이그레이션 파일 생성
    - python manage.py makemigrations
2. 마이그레이션 적용
    - python manage.py migrate

## 관리자 계정 생성
- python manage.py createsuperuser

## 개발 서버 실행
- python manage.py runserver


기본페이지 : http://127.0.0.1:8000/
관리자 페이지 : http://127.0.0.1:8000/admin/
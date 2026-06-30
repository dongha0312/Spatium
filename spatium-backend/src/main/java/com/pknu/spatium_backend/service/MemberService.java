package com.pknu.spatium_backend.service;

import org.springframework.stereotype.Service;

import com.pknu.spatium_backend.repository.MemberRepository;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Service
@RequiredArgsConstructor
@Slf4j
public class MemberService {

    private final MemberRepository memberRepository;

}

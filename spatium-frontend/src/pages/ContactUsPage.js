import React from "react";
import "../styles/ContactUsPage.css";
import Header from "../components/Header";
import Footer from "../components/Footer";

const CONTACT_EMAIL = "contact@spatium.com";

function ContactUsPage() {
  return (
    <div className="cu-root">
      <Header prefix="cu" />

      <main className="cu-main">
        <section className="cu-card" aria-labelledby="contact-title">
          <p className="cu-eyebrow">Contact Us</p>
          <h1 className="cu-title" id="contact-title">
            문의하기
          </h1>
          <p className="cu-description">
            SPATIUM에 궁금한 점이 있으시면 아래 이메일로 문의해 주세요.
          </p>

          <div className="cu-email-box">
            <span className="cu-email-label">Email</span>
            <a className="cu-email" href={`mailto:${CONTACT_EMAIL}`}>
              {CONTACT_EMAIL}
            </a>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}

export default ContactUsPage;

from api.services.fault_rag import DEFAULT_SOURCE_PDF_URL, ingest_fault_pdf


if __name__ == "__main__":
    rows = ingest_fault_pdf(DEFAULT_SOURCE_PDF_URL)
    print(f"Indexed {len(rows)} fault code rows.")

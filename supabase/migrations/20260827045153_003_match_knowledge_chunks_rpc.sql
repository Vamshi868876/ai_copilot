/*
# Create match_knowledge_chunks RPC function

## Purpose
Creates a PostgreSQL function that performs pgvector similarity search
(cosine distance) on the `knowledge_chunks` table, returning the top-K
most similar chunks to a query embedding. This is the core of the RAG
retrieval pipeline.

## Security
- SECURITY DEFINER so it can run with elevated privileges to read
  knowledge_chunks (which has RLS enabled). The function itself does
  NOT enforce access control — the caller (edge function) filters
  results by access_level AFTER retrieval as defense in depth. RLS
  policies on knowledge_chunks also apply.
- The function accepts an optional `filter_access_levels` array to
  pre-filter by access level at the database level.
*/

CREATE OR REPLACE FUNCTION match_knowledge_chunks(
  query_embedding vector(1536),
  match_count integer DEFAULT 5,
  filter_access_levels text[] DEFAULT NULL
)
RETURNS TABLE (
  chunk_id uuid,
  document_id text,
  content text,
  document_type text,
  department text,
  access_level doc_access_level,
  source text,
  title text,
  similarity float
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    kc.chunk_id,
    kc.document_id,
    kc.content,
    kc.document_type,
    kc.department,
    kc.access_level,
    kc.source,
    kd.title,
    1 - (kc.embedding <=> query_embedding) AS similarity
  FROM knowledge_chunks kc
  JOIN knowledge_documents kd ON kd.document_id = kc.document_id
  WHERE
    (filter_access_levels IS NULL OR kc.access_level::text = ANY(filter_access_levels))
    AND kc.embedding IS NOT NULL
  ORDER BY kc.embedding <=> query_embedding
  LIMIT match_count;
$$;

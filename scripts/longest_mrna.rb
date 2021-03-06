#!/usr/bin/env ruby

require 'set'
require 'tempfile'

require 'bio/db/gff'

# Read and parse GFF file into memory.
all_records = Bio::GFF::GFF3.new(File.read('ref_Si_gnG_scaffolds.no_mt.comments_stripped.gff3')).records

# Get all mRNA ids.
mrnas = all_records.select {|rec| rec.feature_type == 'mRNA'}
mrnas = mrnas.group_by {|rec| rec.attributes.assoc('Parent').last }
longest_mrnas = mrnas.map do |k, v|
  v.sort_by{|r| r.end - r.start}.first
end
longest_mrna_ids = Set.new longest_mrnas.map(&:id)

# Subset and process the annotations.
selected = Hash.new { |h, k| h[k] = [] }
all_records.each do |rec|
  key = 'ID'     if rec.feature_type == 'mRNA'
  key = 'Parent' if rec.feature_type =~ /exon|CDS/
  val = key && rec.attributes.assoc(key).last
  if val && longest_mrna_ids.include?(val)
    selected[val] << rec
  end
end
selected.each do |_, records|
  mrna = records.find { |rec| rec.feature_type == 'mRNA'}
  records.reject! { |rec| rec.feature_type == 'mRNA'}

  mrna.attributes.delete mrna.attributes.assoc('Parent')
  mrna.start = records.map(&:start).min
  mrna.end = records.map(&:end).max

  count = Hash.new { |h, k| h[k] = 0 }
  records.each do |rec|
    count[rec.feature_type] += 1
    rec.attributes.assoc('ID')[1] =
      "#{mrna.id}:#{rec.feature_type}:#{count[rec.feature_type]}"
  end

  records.unshift mrna
end

temp = Tempfile.open('longest_mrna', '.')
temp.write("##gff-version 3\n")
temp.write(selected.values.flatten.map(&:to_s).join)
temp.close
system "gt gff3 -sort -retainids -addids #{temp.path} >"                       \
       " NCBI_Si_gnG_v100-longest_mRNA.gff3"
system "gt extractfeat -type exon -join -retainids -coords"                    \
       " -seqfile 13686_ref_Si_gnG_chrUn.by_accession.fa -matchdescstart"      \
       " NCBI_Si_gnG_v100-longest_mRNA.gff3 >"                                 \
       " NCBI_Si_gnG_v100-longest_mRNA.cdna.fa"
system "gt extractfeat -type CDS -join -retainids -coords"                     \
       " -seqfile 13686_ref_Si_gnG_chrUn.by_accession.fa -matchdescstart"      \
       " NCBI_Si_gnG_v100-longest_mRNA.gff3 >"                                 \
       " NCBI_Si_gnG_v100-longest_mRNA.cds.fa"
system "gt extractfeat -type CDS -join -translate -retainids -coords"          \
       " -seqfile 13686_ref_Si_gnG_chrUn.by_accession.fa -matchdescstart"      \
       " NCBI_Si_gnG_v100-longest_mRNA.gff3 >"                                 \
       " NCBI_Si_gnG_v100-longest_mRNA.pep.fa"
temp.unlink

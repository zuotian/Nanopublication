require 'rdf'
require 'logger'
require 'slop'
require_relative 'converter'


# Convert txt file generated by Concept Profile Matching texting mining method.
#
# Input file format:
#   concept1_id concept1_external_id concept2_id concept2_external_id match_score p_value {top 10 concepts in JSON}
class CPM_Nanopub_Converter < RDF_Nanopub_Converter

  SIO= RDF::Vocabulary.new('http://semanticscience.org/resource/')
  GDA = RDF::Vocabulary.new('http://rdf.biosemantics.org/dataset/gene_disease_associations#')
  PPA = RDF::Vocabulary.new('http://rdf.biosemantics.org/dataset/protein_protein_associations#')

  def initialize

    super

    # for statistics
    @concept1_hash = Hash.new(0)
    @concept2_hash = Hash.new(0)
    @no_null_genes = 0
    @no_null_omims = 0
  end

  def convert_header_row(row)
    # do nothing
  end

  def convert_row(row)
    tokens = row.split
    concept1_id = tokens[1]
    concept2_id = tokens[3]
    p_value = sprintf('%.3E', tokens[5]).to_f # round it to 3 significant digit

    if concept2_id == 'null'
      @logger.info("line #{@line_number.to_s} has no gene id. skipped.")
      @no_null_genes += 1
      return
    end

    if concept1_id == 'null'
      @logger.info("line #{@line_number.to_s} has no omim id. skipped.")
      @no_null_omims += 1
      return
    end

    if p_value > @options[:p_value_cutoff].to_f
      @logger.warning("** line #{@line_number.to_s} has a p-value greater than #{@options[:p_value_cutoff]}. skipped. **")
      return
    end


    @concept1_hash[concept1_id] += 1
    @concept2_hash[concept2_id] += 1
    @row_index += 1

    case @options[:subtype]
      when 'gda'
        @base = RDF::Vocabulary.new("#{@options[:base_url]}/gene_disease_associations/")
        create_gda_nanopub(concept1_id, concept2_id, p_value)
      when 'ppa'
        @base = RDF::Vocabulary.new("#{@options[:base_url]}/protein_protein_associations/")
        create_ppi_nanopub(concept1_id, concept2_id, p_value)
      else
        throw ArgumentError.new("Subtype #{@options[:subtype]} is not supported.")
    end
  end


  protected
  def get_options
    options = Slop.parse(:help => true) do
      banner "ruby concept_profile_matching.rb [options]\n"
      on :base_url=, :default => 'http://rdf.biosemantics.org/nanopubs/cpm'
      on :p_value_cutoff=, 'P-value cutoff, default = 0.05', :default => '0.05'
      on :subtype=, 'nanopub subtype, choose from [gda, ppa], default is gda', :default => 'gda'
    end

    super.merge(options)
  end

  protected
  def create_gda_nanopub(omim_id, gene_id, p_value)

    # setup nanopub
    nanopub = RDF::Vocabulary.new(@base[@row_index.to_s.rjust(6, '0')])
    assertion = nanopub['#assertion']
    provenance = nanopub['#provenance']
    publication_info = nanopub['#publicationInfo']

    # main graph
    create_main_graph(nanopub, assertion, provenance, publication_info)

    # assertion graph
    association = GDA["association_#{@row_index.to_s.rjust(6, '0')}"]
    association_p_value = GDA["association_#{@row_index.to_s.rjust(6, '0')}_p_value"]
    save(assertion, [
        [association, RDF.type, SIO['statistical-association']],
        [association, SIO['refers-to'], RDF::URI.new("http://bio2rdf.org/geneid:#{gene_id}")],
        [association, SIO['refers-to'], RDF::URI.new("http://bio2rdf.org/omim:#{omim_id.match(/OM_(\d+)/)[1]}")],
        [association, SIO['has-measurement-value'], association_p_value],
        [association_p_value, RDF.type, SIO['probability-value']],
        [association_p_value, SIO['has-value'], RDF::Literal.new(p_value, :datatype => XSD.float)]
    ])

    # provenance graph
    create_gda_provenance_graph(provenance, assertion)

    # publication info graph
    create_publication_info_graph(publication_info, nanopub)

    puts "inserted nanopub <#{nanopub}>"
  end

  protected
  def create_ppi_nanopub(protein1, protein2, p_value)

    # setup nanopub
    nanopub = RDF::Vocabulary.new(@base[@row_index.to_s.rjust(6, '0')])
    assertion = nanopub['#assertion']
    provenance = nanopub['#provenance']
    publication_info = nanopub['#publicationInfo']

    # main graph
    create_main_graph(nanopub, assertion, provenance, publication_info)

    # assertion graph
    association = PPA["association_#{@row_index.to_s.rjust(6, '0')}"]
    association_p_value = PPA["association_#{@row_index.to_s.rjust(6, '0')}_p_value"]
    save(assertion, [
        [association, RDF.type, SIO['statistical-association']],
        [association, SIO['refers-to'], RDF::URI.new("http://bio2rdf.org/geneid:#{protein1}")],
        [association, SIO['refers-to'], RDF::URI.new("http://bio2rdf.org/geneid:#{protein2}")],
        [association, SIO['has-measurement-value'], association_p_value],
        [association_p_value, RDF.type, SIO['probability-value']],
        [association_p_value, SIO['has-value'], RDF::Literal.new(p_value, :datatype => XSD.float)]
    ])

    # provenance graph
    create_ppi_provenance_graph(provenance, assertion)

    # publication info graph
    create_publication_info_graph(publication_info, nanopub)

    puts "inserted nanopub <#{nanopub}>"
  end

  private
  def create_gda_provenance_graph(provenance, assertion)
    save(provenance, [
        [assertion, PROV.wasDerivedFrom, RDF::URI.new('http://rdf.biosemantics.org/vocabularies/text_mining#gene_disease_concept_profiles_1980_2010')],
        [assertion, PROV.wasGeneratedBy, RDF::URI.new('http://rdf.biosemantics.org/vocabularies/text_mining#gene_disease_concept_profiles_matching_1980_2010')]
    ])
  end

  private
  def create_ppi_provenance_graph(provenance, assertion)
    save(provenance, [
        [assertion, PROV.wasDerivedFrom, RDF::URI.new('http://rdf.biosemantics.org/vocabularies/text_mining#protein_protein_concept_profiles_1980_2010')],
        [assertion, PROV.wasGeneratedBy, RDF::URI.new('http://rdf.biosemantics.org/vocabularies/text_mining#protein_protein_concept_profiles_matching_1980_2010')]
    ])
  end

  private
  def create_publication_info_graph(publication_info, nanopub)
    save(publication_info, [
        [nanopub, DC.rights, RDF::URI.new('http://creativecommons.org/licenses/by/3.0/')],
        [nanopub, DC.rightsHolder, RDF::URI.new('http://biosemantics.org')],
        [nanopub, PAV.authoredBy, RDF::URI.new('http://www.researcherid.com/rid/B-6035-2012')],
        [nanopub, PAV.authoredBy, RDF::URI.new('http://www.researcherid.com/rid/B-5927-2012')],
        [nanopub, PAV.createdBy, RDF::URI.new('http://www.researcherid.com/rid/B-5852-2012')],
        [nanopub, DC.created, RDF::Literal.new(Time.now.utc, :datatype => XSD.dateTime)]
    ])
  end
end


# do the work
CPM_Nanopub_Converter.new.convert